//
//  ShuttleFullScreenMapView.swift
//  GM Assistant
//
//  Full-screen, pannable live shuttle map presented from the reservation
//  home mini-map. It reuses the SAME `ShuttleTrackingService` instance (no
//  second Firestore listener is created) and renders the same gliding pins,
//  live pulse, and meeting-point flag as the mini-map — just full-bleed and
//  interactive, with the ETA shown as a floating top card.
//

import SwiftUI
import MapKit
import CoreLocation

struct ShuttleFullScreenMapView: View {
    @Environment(\.dismiss) private var dismiss

    /// The live tracker owned by `ReservationHomeView`. Passed in so this screen
    /// observes the existing listener rather than spinning up a second one.
    let tracking: ShuttleTrackingService

    @State private var camera: MapCameraPosition = .automatic
    @State private var displayedCoords: [String: CLLocationCoordinate2D] = [:]
    @State private var didInitialFit = false

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
                .ignoresSafeArea()
            floatingHeader
        }
        .onAppear { syncMap(animated: false) }
        .onChange(of: tracking.drivers) { _, _ in
            syncMap()
        }
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $camera) {
            ForEach(tracking.drivers) { driver in
                Annotation(driver.driverName, coordinate: displayedCoords[driver.id] ?? driver.coordinate) {
                    // 1 s clock so the pin greys the instant the driver goes stale,
                    // independent of the coordinate-glide animation.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let stale = driver.isStale(asOf: context.date)
                        ZStack {
                            if !stale {
                                ShuttleLivePulse()
                            }
                            Circle()
                                .fill(stale ? Color.gray : GMTheme.accent)
                            Image(systemName: "bus.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 40, height: 40)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    }
                }
            }
            if let mp = tracking.meetingPoint {
                Annotation(tracking.meetingLabel ?? String(localized: "shuttle_meeting_point"), coordinate: mp) {
                    Image(systemName: "flag.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white, GMTheme.danger)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }

    // MARK: - Floating header

    private var floatingHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            etaCard
            Spacer(minLength: 0)
            closeButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Mirrors the mini-map's ETA headline, wrapped in a floating card so it
    /// stays legible over the map.
    private var etaCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 4) {
                if let best = tracking.bestDriver(asOf: context.date) {
                    let stale = best.isStale(asOf: context.date)
                    if let minutes = tracking.etaMinutes {
                        HStack(spacing: 8) {
                            ShuttlePulsingDot(color: stale ? GMTheme.warning : GMTheme.accent)
                            Text(String(format: String(localized: "shuttle_eta_minutes"), minutes))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(GMTheme.accent)
                        }
                        if !tracking.etaIsRouteBased {
                            Text("shuttle_eta_estimated")
                                .font(GMTheme.bodyFont(12))
                                .foregroundStyle(GMTheme.textSecondary)
                        }
                    } else {
                        HStack(spacing: 8) {
                            ShuttlePulsingDot(color: stale ? GMTheme.warning : GMTheme.accent)
                            Text("shuttle_on_the_way")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(GMTheme.accent)
                        }
                    }
                    if stale {
                        Label("shuttle_signal_weak", systemImage: "wifi.exclamationmark")
                            .font(GMTheme.bodyFont(12))
                            .foregroundStyle(GMTheme.warning)
                    }
                } else {
                    Label("shuttle_location_unavailable", systemImage: "exclamationmark.circle")
                        .font(GMTheme.bodyFont(13))
                        .foregroundStyle(GMTheme.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(GMTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.cardCornerRadius, style: .continuous))
            .shadow(color: GMTheme.cardShadowColor, radius: 10, x: 0, y: 4)
        }
    }

    private var closeButton: some View {
        Button {
            Haptics.light()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(GMTheme.textPrimary)
                .frame(width: 40, height: 40)
                .background(GMTheme.card)
                .clipShape(Circle())
                .shadow(color: GMTheme.cardShadowColor, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("shuttle_close_map"))
    }

    // MARK: - Pin glide + camera

    /// Glides pins toward their latest coordinates. The camera is fitted once on
    /// appear; afterwards it is left to the customer's own pan/zoom so live
    /// updates never yank the map out from under their fingers.
    private func syncMap(animated: Bool = true) {
        var next: [String: CLLocationCoordinate2D] = [:]
        for driver in tracking.drivers {
            next[driver.id] = driver.coordinate
        }
        var coords = tracking.drivers.map(\.coordinate)
        if let mp = tracking.meetingPoint { coords.append(mp) }

        if animated {
            withAnimation(.linear(duration: 2.2)) {
                displayedCoords = next
            }
        } else {
            displayedCoords = next
        }

        guard !didInitialFit, !coords.isEmpty else { return }
        didInitialFit = true
        camera = .region(ReservationHomeView.fittedRegion(for: coords))
    }
}
