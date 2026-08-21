//
//  ShuttleTrackingService.swift
//  GM Assistant
//
//  Live shuttle tracking for customers who requested the shuttle:
//  - Firestore listener on franchises/{fid}/shuttleDriverLocations
//    (isSharing == true, limit 12) — read access is granted by rules to
//    holders of a valid customerSessions doc for the same franchise.
//  - "Your driver is X min away" ETA: MKDirections (driving), throttled to
//    one request per ≥20 s and only after meaningful driver movement, with
//    a straight-line 30 km/h fallback when routing fails.
//  - Destination priority: franchise meeting point (publicConfig) →
//    customer's own location (WhenInUse, only requested when needed) →
//    no ETA (drivers still shown on the mini-map).
//  Every failure mode degrades to a calm UI state — never a crash, never
//  ancient data presented as live.
//

import Foundation
import Observation
import CoreLocation
import MapKit
import FirebaseFirestore

@Observable
@MainActor
final class ShuttleTrackingService {
    private(set) var drivers: [ShuttleDriverLocation] = []
    /// Listener failed (permission-denied on expired/mismatched session, network, …).
    /// The UI hides the live section gracefully and keeps the static confirmation.
    private(set) var listenerFailed = false
    private(set) var etaSeconds: Int?
    /// true when the current ETA came from MKDirections; false for the
    /// straight-line 30 km/h estimate (UI shows a "~ estimated" hint).
    private(set) var etaIsRouteBased = false

    let meetingPoint: CLLocationCoordinate2D?
    let meetingLabel: String?

    private let franchiseId: String
    private var listener: ListenerRegistration?
    private var countdownTimer: Timer?
    private var recomputeTimer: Timer?

    // MKDirections throttle state
    private var lastDirectionsAt: Date?
    private var lastDirectionsDriverLocation: CLLocation?
    private var consecutiveDirectionsFailures = 0
    private var directionsInFlight = false
    private let directionsMinInterval: TimeInterval = 20
    private let directionsRetryBackoff: TimeInterval = 120
    /// Straight-line fallback speed: 30 km/h ≈ 8.33 m/s.
    private let fallbackSpeedMps: Double = 8.33

    private var customerLocationProvider: CustomerLocationProvider?
    private var customerCoordinate: CLLocationCoordinate2D?

    init(reservation: CustomerReservation) {
        franchiseId = reservation.franchiseId
        meetingPoint = reservation.shuttleMeetingCoordinate
        meetingLabel = reservation.shuttleMeetingLabel
    }

    /// Best (nearest to the destination) driver whose data is not ancient.
    var bestDriver: ShuttleDriverLocation? {
        drivers.first { !$0.isExpired }
    }

    /// Same as `bestDriver` but evaluated against an explicit clock, so a view's
    /// `TimelineView` tick can flip a driver to "unavailable" the moment it
    /// crosses the 180 s expiry — even when no new Firestore write arrives.
    func bestDriver(asOf now: Date) -> ShuttleDriverLocation? {
        drivers.first { !$0.isExpired(asOf: now) }
    }

    /// Rounded-up display minutes, never below 1.
    var etaMinutes: Int? {
        etaSeconds.map { max(1, Int(ceil(Double($0) / 60))) }
    }

    // MARK: - Lifecycle

    func start() {
        guard listener == nil else { return }
        listenerFailed = false
        listener = Firestore.firestore()
            .collection("franchises")
            .document(franchiseId)
            .collection("shuttleDriverLocations")
            .whereField("isSharing", isEqualTo: true)
            .limit(to: 12)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    print("shuttleDriverLocations listener: \(error.localizedDescription)")
                    Task { @MainActor in
                        self.listenerFailed = true
                        self.drivers = []
                        self.etaSeconds = nil
                        self.etaIsRouteBased = false
                    }
                    return
                }
                let fetched: [ShuttleDriverLocation] = (snapshot?.documents ?? [])
                    .compactMap { ShuttleDriverLocation.from(document: $0) }
                Task { @MainActor in
                    self.listenerFailed = false
                    self.drivers = self.sortedByDestinationDistance(fetched)
                    self.recomputeETA()
                }
            }
        startTimers()
        // Only ask for the customer's location when there is no configured
        // meeting point — otherwise the app needs no location permission at all.
        if meetingPoint == nil, customerLocationProvider == nil {
            let provider = CustomerLocationProvider { [weak self] coordinate in
                guard let self else { return }
                self.customerCoordinate = coordinate
                self.recomputeETA()
            }
            customerLocationProvider = provider
            provider.startIfPossible()
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
        stopTimers()
        customerLocationProvider?.stop()
        drivers = []
        etaSeconds = nil
        etaIsRouteBased = false
        directionsInFlight = false
        lastDirectionsAt = nil
        lastDirectionsDriverLocation = nil
        consecutiveDirectionsFailures = 0
    }

    private func startTimers() {
        if countdownTimer == nil {
            // Live countdown between recomputes; floored so the display never
            // dips below "1 min" from ticking alone.
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    guard let eta = self.etaSeconds, eta > 60 else { return }
                    self.etaSeconds = eta - 1
                }
            }
        }
        if recomputeTimer == nil {
            // Re-evaluates staleness/expiry and refreshes the route even when
            // the only Firestore traffic is the driver's 45 s heartbeat.
            recomputeTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.recomputeETA()
                }
            }
        }
    }

    private func stopTimers() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        recomputeTimer?.invalidate()
        recomputeTimer = nil
    }

    // MARK: - ETA engine

    private var destinationCoordinate: CLLocationCoordinate2D? {
        meetingPoint ?? customerCoordinate
    }

    private func sortedByDestinationDistance(_ list: [ShuttleDriverLocation]) -> [ShuttleDriverLocation] {
        guard let dest = destinationCoordinate else { return list }
        let destLoc = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
        return list.sorted {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: destLoc) <
                CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: destLoc)
        }
    }

    private func recomputeETA() {
        guard let driver = bestDriver else {
            etaSeconds = nil
            etaIsRouteBased = false
            return
        }
        guard let destination = destinationCoordinate else {
            // No anchor to measure against — mini-map still shows the shuttle.
            etaSeconds = nil
            etaIsRouteBased = false
            return
        }
        let driverLocation = CLLocation(latitude: driver.latitude, longitude: driver.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let straightSeconds = Int(driverLocation.distance(from: destinationLocation) / fallbackSpeedMps)

        // Always keep a sane value on screen; the route refines it.
        if etaSeconds == nil || !etaIsRouteBased {
            etaSeconds = straightSeconds
            etaIsRouteBased = false
        }

        // Throttled MKDirections: ≥20 s between requests AND meaningful driver
        // movement (>100 m) unless we have no route-based value yet. After two
        // consecutive failures, back off to straight-line for 120 s.
        let now = Date()
        let intervalOK = lastDirectionsAt.map { now.timeIntervalSince($0) >= directionsMinInterval } ?? true
        let movedEnough = lastDirectionsDriverLocation.map { driverLocation.distance(from: $0) > 100 } ?? true
        let backoffOver = lastDirectionsAt.map { now.timeIntervalSince($0) >= directionsRetryBackoff } ?? true
        guard !directionsInFlight,
              intervalOK,
              movedEnough || !etaIsRouteBased,
              consecutiveDirectionsFailures < 2 || backoffOver else { return }
        if consecutiveDirectionsFailures >= 2 { consecutiveDirectionsFailures = 0 }

        directionsInFlight = true
        lastDirectionsAt = now
        lastDirectionsDriverLocation = driverLocation

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: driverLocation.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        let directions = MKDirections(request: request)
        Task {
            do {
                let response = try await directions.calculate()
                directionsInFlight = false
                consecutiveDirectionsFailures = 0
                if let route = response.routes.first {
                    etaSeconds = Int(route.expectedTravelTime)
                    etaIsRouteBased = true
                }
            } catch {
                directionsInFlight = false
                consecutiveDirectionsFailures += 1
                etaSeconds = straightSeconds
                etaIsRouteBased = false
            }
        }
    }
}

/// Minimal WhenInUse location wrapper — used ONLY when the franchise has no
/// configured shuttle meeting point, to anchor the ETA at the customer.
/// Delegate callbacks are nonisolated and hop back to the main actor.
@MainActor
private final class CustomerLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let onCoordinate: (CLLocationCoordinate2D) -> Void

    init(onCoordinate: @escaping (CLLocationCoordinate2D) -> Void) {
        self.onCoordinate = onCoordinate
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    func startIfPossible() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break // denied/restricted → ETA silently unavailable
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.onCoordinate(coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silent — ETA falls back to no-anchor mode.
    }
}
