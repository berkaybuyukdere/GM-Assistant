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
                            Circle()
                                .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                            Image(systemName: "bus.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 38, height: 38)
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    }
                }
            }
            if let mp = tracking.meetingPoint {
                Annotation(tracking.meetingLabel ?? String(localized: "shuttle_meeting_point"), coordinate: mp) {
                    ZStack {
                        Circle().fill(GMTheme.danger)
                        Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2)
                        Image(systemName: "flag.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
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
            VStack(alignment: .leading, spacing: 5) {
                if let best = tracking.bestDriver(asOf: context.date) {
                    let stale = best.isStale(asOf: context.date)
                    if let minutes = tracking.etaMinutes {
                        HStack(spacing: 9) {
                            ShuttlePulsingDot(color: stale ? GMTheme.warning : GMTheme.accent)
                            Text(String(format: String(localized: "shuttle_eta_minutes"), minutes))
                                .font(GMTheme.ui(18, .bold))
                                .monospacedDigit()
                                .foregroundStyle(stale ? GMTheme.warning : GMTheme.accentText)
                        }
                        if !tracking.etaIsRouteBased {
                            Text("shuttle_eta_estimated").gmCaption(11.5, color: GMTheme.textFaint)
                        }
                    } else {
                        HStack(spacing: 9) {
                            ShuttlePulsingDot(color: stale ? GMTheme.warning : GMTheme.accent)
                            Text("shuttle_on_the_way")
                                .font(GMTheme.ui(15, .semibold))
                                .foregroundStyle(GMTheme.accentText)
                        }
                    }
                    if stale {
                        Label("shuttle_signal_weak", systemImage: "wifi.exclamationmark")
                            .font(GMTheme.ui(11.5))
                            .foregroundStyle(GMTheme.warning)
                    }
                } else {
                    Label("shuttle_location_unavailable", systemImage: "exclamationmark.circle")
                        .font(GMTheme.ui(12.5))
                        .foregroundStyle(GMTheme.textMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
            .gmBorder(GMTheme.border)
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
    }

    private var closeButton: some View {
        Button {
            Haptics.tap()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GMTheme.textPrimary)
                .frame(width: 40, height: 40)
                .background(.regularMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
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
