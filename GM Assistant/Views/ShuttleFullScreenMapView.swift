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
                            RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                                .fill(stale ? Color.gray : GMTheme.accent)
                            RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                                .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                            Image(systemName: "bus.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color(hex: 0x08120C))
                        }
                        .frame(width: 34, height: 34)
                    }
                }
            }
            if let mp = tracking.meetingPoint {
                Annotation(tracking.meetingLabel ?? String(localized: "shuttle_meeting_point"), coordinate: mp) {
                    ZStack {
                        RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                            .fill(GMTheme.danger)
                        RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                            .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                        Image(systemName: "flag.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 28, height: 28)
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
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            ShuttlePulsingDot(color: stale ? GMTheme.warning : GMTheme.accent)
                            Text(String(format: String(localized: "shuttle_eta_minutes"), minutes))
                                .font(GMTheme.mono(18, .bold))
                                .foregroundStyle(stale ? GMTheme.warning : GMTheme.accentBright)
                        }
                        if !tracking.etaIsRouteBased {
                            Text("shuttle_eta_estimated")
                                .gmMicroLabel(8.5, color: GMTheme.textFaint)
                        }
                    } else {
                        HStack(spacing: 9) {
                            ShuttlePulsingDot(color: stale ? GMTheme.warning : GMTheme.accent)
                            Text("shuttle_on_the_way")
                                .gmMicroLabel(10, color: GMTheme.accentBright)
                        }
                    }
                    if stale {
                        Label("shuttle_signal_weak", systemImage: "wifi.exclamationmark")
                            .gmMicroLabel(8.5, color: GMTheme.warning)
                    }
                } else {
                    Label("shuttle_location_unavailable", systemImage: "exclamationmark.circle")
                        .gmMicroLabel(9, color: GMTheme.textMuted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(GMTheme.surface.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
            .gmBorder(GMTheme.borderStrong)
        }
    }

    private var closeButton: some View {
        Button {
            Haptics.light()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(GMTheme.textPrimary)
                .frame(width: 38, height: 38)
                .background(GMTheme.surface.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
                .gmBorder(GMTheme.borderStrong)
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
