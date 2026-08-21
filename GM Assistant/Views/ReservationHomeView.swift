//
//  ReservationHomeView.swift
//  GM Assistant
//
//  Reservation dashboard: vehicle + reservation panels, photo upload
//  actions (check-out / return), shuttle yes-no toggle,
//  roadside assistance + GM office call buttons, and the customer's
//  own submissions (live).
//
//  Laid out as an operations console: a session strip at the top, then
//  stacked hairline panels, each titled with a micro label.
//

import SwiftUI
import UIKit
import MapKit
import CoreLocation

struct ReservationHomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    let reservation: CustomerReservation

    @State private var photoSheetType: CustomerRecordType?
    @State private var shuttleSaving = false
    @State private var shuttleError = false
    @State private var gallerySession: RemotePhotoGallerySession?
    @State private var noteText = ""
    @State private var noteSaving = false
    @State private var noteSent = false
    @State private var noteError = false
    @FocusState private var noteFieldFocused: Bool

    // Live shuttle tracking (only while the customer's shuttle request is YES)
    @State private var shuttleTracking: ShuttleTrackingService?
    @State private var shuttleCamera: MapCameraPosition = .automatic
    @State private var displayedShuttleCoords: [String: CLLocationCoordinate2D] = [:]
    /// Region the mini-map camera was last fitted to. The camera holds this
    /// frame (WhatsApp-style) while pins glide, and only re-fits when a driver
    /// or the meeting point drifts outside a padded copy of it.
    @State private var lastFitRegion: MKCoordinateRegion?
    @State private var showShuttleFullScreen = false

    private var recordService: CustomerRecordService? { appState.recordService }

    var body: some View {
        NavigationStack {
            ZStack {
                GMCanvas()
                ScrollView {
                    VStack(spacing: 12) {
                        sessionStrip
                        vehiclePanel
                        reservationPanel
                        photoActionsPanel
                        notePanel
                        shuttlePanel
                        assistancePanel
                        submissionsPanel
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .toolbarBackground(GMTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        Rectangle()
                            .fill(GMTheme.accent)
                            .frame(width: 2, height: 12)
                        Text(verbatim: "GM ASSISTANT")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1.3)
                            .foregroundStyle(GMTheme.textPrimary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        appState.endSession()
                    } label: {
                        Text("change_reservation")
                            .gmMicroLabel(9.5, color: GMTheme.accentBright)
                    }
                }
            }
            .sheet(item: $photoSheetType) { type in
                PhotoCaptureView(reservation: reservation, type: type)
            }
            .onAppear { syncShuttleTracking() }
            .onDisappear {
                shuttleTracking?.stop()
                shuttleTracking = nil
            }
            .onChange(of: recordService?.shuttleRequested) { _, _ in
                syncShuttleTracking()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    syncShuttleTracking() // re-attach listener after background
                case .background:
                    shuttleTracking?.stop() // battery + socket hygiene
                default:
                    break
                }
            }
        }
    }

    /// Starts/stops the live tracker so the Firestore listener only runs while
    /// the customer's shuttle request is YES and the app is in the foreground.
    private func syncShuttleTracking() {
        if recordService?.shuttleRequested == true {
            if shuttleTracking == nil {
                shuttleTracking = ShuttleTrackingService(reservation: reservation)
            }
            shuttleTracking?.start()
        } else {
            shuttleTracking?.stop()
            shuttleTracking = nil
            displayedShuttleCoords = [:]
            lastFitRegion = nil
        }
    }

    // MARK: - Session strip

    private var sessionStrip: some View {
        HStack(spacing: 9) {
            GMStatusDot(color: GMTheme.accent, size: 6, pulsing: true)
            Text(verbatim: "SESSION ACTIVE")
                .gmMicroLabel(9, color: GMTheme.textSecondary)
            Spacer(minLength: 8)
            Text(reservation.resKodu)
                .font(GMTheme.mono(11, .semibold))
                .tracking(0.6)
                .foregroundStyle(GMTheme.accentBright)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(GMTheme.surface.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
        .gmBorder()
    }

    // MARK: - Vehicle & reservation

    private var vehiclePanel: some View {
        GMPanel("vehicle_label") {
            HStack(spacing: 13) {
                GMIconFrame(systemName: "car.side.fill", size: 44)
                VStack(alignment: .leading, spacing: 6) {
                    if !reservation.vehicleDisplayName.isEmpty {
                        Text(reservation.vehicleDisplayName)
                            .font(GMTheme.ui(18, .bold))
                            .tracking(0.3)
                            .foregroundStyle(GMTheme.textPrimary)
                    }
                    if !reservation.aracPlaka.isEmpty {
                        GMChip(text: reservation.aracPlaka, size: 14)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var reservationPanel: some View {
        GMPanel("reservation_label", spacing: 9) {
            if let name = reservation.customerName {
                GMDataRow(label: "customer", value: name, mono: false)
                rowDivider
            }
            if let checkoutAt = reservation.checkoutAt {
                GMDataRow(label: "pickup_date", value: Self.dateFormatter.string(from: checkoutAt))
                rowDivider
            }
            if let plannedReturn = reservation.plannedReturnAt {
                GMDataRow(label: "planned_return", value: Self.dateFormatter.string(from: plannedReturn))
                rowDivider
            }
            if let branch = reservation.pickUpBranch {
                GMDataRow(label: "pickup_branch", value: branch, mono: false)
                rowDivider
            }
            if let branch = reservation.dropOffBranch {
                GMDataRow(label: "dropoff_branch", value: branch, mono: false)
            }
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(GMTheme.divider)
            .frame(height: GMTheme.hairline)
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    // MARK: - Photos

    private var photoActionsPanel: some View {
        GMPanel("add_photos", spacing: 8) {
            photoActionButton(
                type: .checkoutPhotos,
                titleKey: "checkout_photos",
                icon: "arrow.right.circle.fill"
            )
            photoActionButton(
                type: .returnPhotos,
                titleKey: "return_photos",
                icon: "arrow.uturn.backward.circle.fill"
            )
        }
    }

    private func photoActionButton(
        type: CustomerRecordType,
        titleKey: LocalizedStringKey,
        icon: String,
        tint: Color = GMTheme.accent
    ) -> some View {
        Button {
            Haptics.light()
            photoSheetType = type
        } label: {
            HStack(spacing: 11) {
                GMIconFrame(systemName: icon, tint: tint, size: 32)
                Text(titleKey)
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(GMTheme.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(GMTheme.textFaint)
            }
            .padding(11)
            .background(GMTheme.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
            .gmBorder(GMTheme.border, radius: GMTheme.radiusTight)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Note

    private var notePanel: some View {
        GMPanel("write_a_note", spacing: 11) {
            TextField("note_placeholder", text: $noteText, axis: .vertical)
                .font(GMTheme.ui(13.5))
                .foregroundStyle(GMTheme.textPrimary)
                .lineLimit(2...4)
                .focused($noteFieldFocused)
                .padding(11)
                .background(GMTheme.surfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
                .gmBorder(
                    noteFieldFocused ? GMTheme.accent.opacity(0.5) : GMTheme.border,
                    radius: GMTheme.radiusTight
                )
                .animation(.easeOut(duration: 0.15), value: noteFieldFocused)

            HStack(spacing: 10) {
                if noteSent {
                    HStack(spacing: 5) {
                        GMStatusDot(color: GMTheme.accent, size: 5)
                        Text("note_sent").gmMicroLabel(9, color: GMTheme.accentBright)
                    }
                    .transition(.opacity)
                } else if noteError {
                    HStack(spacing: 5) {
                        GMStatusDot(color: GMTheme.danger, size: 5)
                        Text("error_unknown").gmMicroLabel(9, color: GMTheme.danger)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    sendNote()
                } label: {
                    if noteSaving {
                        ProgressView().tint(Color(hex: 0x08120C))
                    } else {
                        Label("send_note", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(GMPrimaryButtonStyle(height: 40))
                .frame(width: 150)
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || noteSaving)
            }
            .animation(.easeOut(duration: 0.2), value: noteSent)
        }
    }

    private func sendNote() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !noteSaving else { return }
        Haptics.light()
        noteFieldFocused = false
        noteSaving = true
        noteError = false
        noteSent = false
        Task {
            do {
                try await appState.recordService?.addNote(text: trimmed)
                noteText = ""
                withAnimation { noteSent = true }
                Haptics.success()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation { noteSent = false }
            } catch {
                noteError = true
                Haptics.error()
            }
            noteSaving = false
        }
    }

    // MARK: - Shuttle

    private var shuttlePanel: some View {
        GMPanel("shuttle_question", spacing: 11) {
            HStack(spacing: 8) {
                shuttleChoiceButton(titleKey: "yes", value: true)
                shuttleChoiceButton(titleKey: "no", value: false)
            }

            if let current = recordService?.shuttleRequested {
                HStack(spacing: 6) {
                    GMStatusDot(
                        color: current ? GMTheme.accent : GMTheme.textFaint,
                        size: 5
                    )
                    Text(current ? "shuttle_requested_yes" : "shuttle_requested_no")
                        .gmMicroLabel(9, color: current ? GMTheme.accentBright : GMTheme.textMuted)
                }
            }

            // Live tracking — only when the request is YES; a listener failure
            // (expired session, network) degrades to the static confirmation.
            if recordService?.shuttleRequested == true,
               let tracking = shuttleTracking,
               !tracking.listenerFailed {
                shuttleLiveSection(tracking)
            }

            if shuttleError {
                HStack(spacing: 5) {
                    GMStatusDot(color: GMTheme.danger, size: 5)
                    Text("error_unknown").gmMicroLabel(9, color: GMTheme.danger)
                }
            }
        } accessory: {
            if recordService?.shuttleRequested == true,
               let tracking = shuttleTracking,
               !tracking.listenerFailed,
               !tracking.drivers.isEmpty {
                HStack(spacing: 5) {
                    GMStatusDot(color: GMTheme.accent, size: 5, pulsing: true)
                    Text(verbatim: "LIVE").gmMicroLabel(8.5, color: GMTheme.accentBright)
                }
            }
        }
    }

    // MARK: - Live shuttle tracking UI

    @ViewBuilder
    private func shuttleLiveSection(_ tracking: ShuttleTrackingService) -> some View {
        if tracking.drivers.isEmpty {
            // No drivers sharing right now — calm placeholder, never an empty map.
            HStack(spacing: 8) {
                Image(systemName: "bus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GMTheme.textFaint)
                Text("shuttle_no_driver_yet")
                    .gmMicroLabel(9, color: GMTheme.textMuted)
            }
            .padding(.vertical, 2)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                shuttleEtaHeadline(tracking)
                shuttleMiniMap(tracking)
                shuttleFreshnessCaption(tracking)
            }
            .onChange(of: tracking.drivers) { _, _ in
                syncShuttleMap(tracking)
            }
            .onAppear {
                syncShuttleMap(tracking, animated: false)
            }
        }
    }

    @ViewBuilder
    private func shuttleEtaHeadline(_ tracking: ShuttleTrackingService) -> some View {
        // Periodic 1 s clock: the "X min away" line, weak-signal warning, and the
        // switch to "location unavailable" all re-evaluate every second against
        // `context.date`, so they stay honest even between Firestore writes.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let best = tracking.bestDriver(asOf: context.date) {
                let stale = best.isStale(asOf: context.date)
                VStack(alignment: .leading, spacing: 5) {
                    if let minutes = tracking.etaMinutes {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            ShuttlePulsingDot(color: stale ? GMTheme.warning : GMTheme.accent)
                            Text(String(format: String(localized: "shuttle_eta_minutes"), minutes))
                                .font(GMTheme.mono(19, .bold))
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
                }
            } else {
                // All shared positions are older than 3 minutes — never show an ETA.
                Label("shuttle_location_unavailable", systemImage: "exclamationmark.circle")
                    .gmMicroLabel(9, color: GMTheme.textMuted)
            }
        }
    }

    private func shuttleMiniMap(_ tracking: ShuttleTrackingService) -> some View {
        Map(position: $shuttleCamera, interactionModes: []) {
            ForEach(tracking.drivers) { driver in
                Annotation(driver.driverName, coordinate: displayedShuttleCoords[driver.id] ?? driver.coordinate) {
                    // 1 s clock so the pin greys the instant the driver goes stale,
                    // independent of the map's coordinate-glide animation.
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
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(hex: 0x08120C))
                        }
                        .frame(width: 30, height: 30)
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
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 26, height: 26)
                }
            }
        }
        .frame(height: 172)
        .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
        .gmBorder(GMTheme.borderStrong, radius: GMTheme.radiusTight)
        // The mini-map is non-interactive (interactionModes: []); a tap opens the
        // full-screen, pannable map instead of fighting the panel's scroll view.
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(GMTheme.textPrimary)
                .padding(6)
                .background(GMTheme.background.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
                .gmBorder(GMTheme.borderStrong, radius: GMTheme.radiusTight)
                .padding(7)
        }
        .contentShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
        .onTapGesture {
            Haptics.light()
            showShuttleFullScreen = true
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("shuttle_open_fullscreen"))
        .fullScreenCover(isPresented: $showShuttleFullScreen) {
            ShuttleFullScreenMapView(tracking: tracking)
        }
    }

    @ViewBuilder
    private func shuttleFreshnessCaption(_ tracking: ShuttleTrackingService) -> some View {
        // WhatsApp-live feel: while the signal is fresh we show NO "updated Xs ago"
        // line — the live pulse behind the pin and the "X min away" headline already
        // read as real time. Only once a driver goes stale (>90 s) do we surface the
        // age, in warning color, so the customer knows the dot may have drifted.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let best = tracking.bestDriver(asOf: context.date) ?? tracking.drivers.first,
               best.isStale(asOf: context.date) {
                let age = best.secondsSinceUpdate(asOf: context.date)
                Text(String(format: String(localized: "shuttle_last_update"),
                            ShuttleDriverLocation.ageText(seconds: age)))
                    .gmMicroLabel(8.5, color: GMTheme.warning)
            }
        }
    }

    /// Glides pins towards their latest live coordinates (Uber-style ease) and
    /// keeps the camera steady while they move — only re-fitting the frame when a
    /// driver or the meeting point drifts outside the last-fitted region.
    private func syncShuttleMap(_ tracking: ShuttleTrackingService, animated: Bool = true) {
        var next: [String: CLLocationCoordinate2D] = [:]
        for driver in tracking.drivers {
            next[driver.id] = driver.coordinate
        }
        var coords = tracking.drivers.map(\.coordinate)
        if let mp = tracking.meetingPoint { coords.append(mp) }
        guard !coords.isEmpty else {
            displayedShuttleCoords = next
            return
        }
        let region = Self.fittedRegion(for: coords)
        // WhatsApp-style steadiness: if everything still sits comfortably inside the
        // region we already framed (checked against a padded copy so a pin near the
        // edge triggers a refit *before* it slides off), we leave the camera alone
        // and only glide the pins. The camera re-centers solely when needed.
        let needsRefit: Bool
        if let last = lastFitRegion {
            needsRefit = coords.contains { !Self.region(last, contains: $0) }
        } else {
            needsRefit = true
        }
        if animated {
            // Glide each pin toward its fresh coordinate at constant velocity over
            // ~2.2 s — matched to the driver's 2–3 s publish cadence so motion
            // reads as continuous travel rather than a teleport.
            withAnimation(.linear(duration: 2.2)) {
                displayedShuttleCoords = next
            }
            if needsRefit {
                lastFitRegion = region
                // The camera refit eases separately and more gently so the frame
                // doesn't lurch when it does move.
                withAnimation(.easeInOut(duration: 0.9)) {
                    shuttleCamera = .region(region)
                }
            }
        } else {
            displayedShuttleCoords = next
            lastFitRegion = region
            shuttleCamera = .region(region)
        }
    }

    /// Smallest padded region that frames every supplied coordinate, with a
    /// minimum span so a single stationary driver isn't zoomed in absurdly close.
    static func fittedRegion(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (lats.max()! - lats.min()!) * 1.5 + 0.02),
            longitudeDelta: max(0.02, (lngs.max()! - lngs.min()!) * 1.5 + 0.02)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// True when `coord` sits within the central `insetFactor` of `region` — used
    /// as a hysteresis band so the mini-map only re-centers once a pin approaches
    /// the frame edge rather than on every small live nudge.
    static func region(
        _ region: MKCoordinateRegion,
        contains coord: CLLocationCoordinate2D,
        insetFactor: Double = 0.8
    ) -> Bool {
        let latHalf = region.span.latitudeDelta / 2 * insetFactor
        let lngHalf = region.span.longitudeDelta / 2 * insetFactor
        return abs(coord.latitude - region.center.latitude) <= latHalf
            && abs(coord.longitude - region.center.longitude) <= lngHalf
    }

    private func shuttleChoiceButton(titleKey: LocalizedStringKey, value: Bool) -> some View {
        let isSelected = recordService?.shuttleRequested == value
        return Button {
            guard !shuttleSaving else { return }
            Haptics.light()
            shuttleSaving = true
            shuttleError = false
            Task {
                do {
                    try await recordService?.setShuttleRequested(value)
                    Haptics.success()
                } catch {
                    shuttleError = true
                    Haptics.error()
                }
                shuttleSaving = false
            }
        } label: {
            HStack(spacing: 7) {
                if shuttleSaving && isSelected {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(GMTheme.accentBright)
                } else {
                    GMStatusDot(
                        color: isSelected ? GMTheme.accent : GMTheme.textFaint,
                        size: 5
                    )
                }
                Text(titleKey)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(isSelected ? GMTheme.accentBright : GMTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(isSelected ? GMTheme.accentWash : GMTheme.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
            .gmBorder(
                isSelected ? GMTheme.accent.opacity(0.55) : GMTheme.border,
                radius: GMTheme.radiusTight
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Assistance calls

    private var assistancePanel: some View {
        GMPanel("need_help", spacing: 9) {
            Button {
                Haptics.light()
                call(number: reservation.roadsidePhone)
            } label: {
                Label("roadside_assistance", systemImage: "wrench.and.screwdriver.fill")
            }
            .buttonStyle(GMGhostButtonStyle(color: GMTheme.danger))

            if let office = reservation.officePhone {
                Button {
                    Haptics.light()
                    call(number: office)
                } label: {
                    Label("call_gm_office", systemImage: "phone.fill")
                }
                .buttonStyle(GMPrimaryButtonStyle())
            }
        }
    }

    private func call(number: String) {
        let cleaned = number.replacingOccurrences(of: " ", with: "")
        guard let url = URL(string: "tel://\(cleaned)"),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Submissions

    private var submissionsPanel: some View {
        Group {
            if let records = recordService?.records, !records.isEmpty {
                GMPanel("my_submissions", spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        SubmissionRow(record: record) { startIndex in
                            gallerySession = RemotePhotoGallerySession(
                                urls: record.photos,
                                startIndex: startIndex
                            )
                        }
                        if index < records.count - 1 {
                            Rectangle()
                                .fill(GMTheme.divider)
                                .frame(height: GMTheme.hairline)
                        }
                    }
                } accessory: {
                    HStack(spacing: 5) {
                        GMStatusDot(color: GMTheme.accent, size: 5)
                        Text("sent_to_erp").gmMicroLabel(8.5, color: GMTheme.accentBright)
                    }
                }
            }
        }
        .sheet(item: $gallerySession) { session in
            RemotePhotoGalleryView(session: session)
        }
    }
}

/// Small pulsing "live" indicator next to the shuttle ETA headline.
/// Shared with `ShuttleFullScreenMapView`.
struct ShuttlePulsingDot: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.9), radius: 3)
            .opacity(pulsing ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}

/// Expanding "live radar" ring behind a fresh shuttle pin on the mini-map,
/// reinforcing that the position is updating in real time. Rendered only while
/// the driver is not stale. Shared with `ShuttleFullScreenMapView`.
struct ShuttleLivePulse: View {
    @State private var animating = false

    var body: some View {
        RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
            .stroke(GMTheme.accent.opacity(0.55), lineWidth: 1.5)
            .frame(width: 30, height: 30)
            .scaleEffect(animating ? 2.0 : 0.95)
            .opacity(animating ? 0 : 0.7)
            .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: animating)
            .onAppear { animating = true }
    }
}

/// One row in "My submissions" — type, timestamp, delivery status, and
/// real thumbnails of exactly what was uploaded (tap to view full-screen).
struct SubmissionRow: View {
    let record: CustomerRecord
    var onTapPhoto: (Int) -> Void = { _ in }

    private var titleKey: LocalizedStringKey {
        switch record.type {
        case .checkoutPhotos: return "checkout_photos"
        case .returnPhotos: return "return_photos"
        case .damagePhotos: return "damage_photos"
        case .shuttleRequest: return "shuttle_request"
        case .note: return "note"
        }
    }

    private var icon: String {
        switch record.type {
        case .checkoutPhotos: return "arrow.right.circle.fill"
        case .returnPhotos: return "arrow.uturn.backward.circle.fill"
        case .damagePhotos: return "exclamationmark.triangle.fill"
        case .shuttleRequest: return "bus.fill"
        case .note: return "text.bubble.fill"
        }
    }

    private var isSeen: Bool { record.status == "seen" }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                GMIconFrame(systemName: icon, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(titleKey)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(GMTheme.textPrimary)
                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(GMTheme.mono(10))
                        .foregroundStyle(GMTheme.textFaint)
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    GMStatusDot(color: isSeen ? GMTheme.accent : GMTheme.textFaint, size: 5)
                    Text(verbatim: isSeen ? "SEEN" : "SENT")
                        .gmMicroLabel(8, color: isSeen ? GMTheme.accentBright : GMTheme.textMuted)
                }
            }

            if record.type == .note, let note = record.note, !note.isEmpty {
                HStack(alignment: .top, spacing: 9) {
                    Rectangle()
                        .fill(GMTheme.accent.opacity(0.55))
                        .frame(width: 2)
                    Text(note)
                        .font(GMTheme.ui(12.5))
                        .foregroundStyle(GMTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .background(GMTheme.surfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
            }

            if !record.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(record.photos.enumerated()), id: \.offset) { index, url in
                            Button {
                                onTapPhoto(index)
                            } label: {
                                AsyncImage(url: URL(string: url)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    case .failure:
                                        Image(systemName: "photo")
                                            .foregroundStyle(GMTheme.textFaint)
                                    default:
                                        ProgressView().tint(GMTheme.accent)
                                    }
                                }
                                .frame(width: 66, height: 66)
                                .background(GMTheme.surfaceInset)
                                .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
                                .gmBorder(GMTheme.border, radius: GMTheme.radiusTight)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }
}

extension CustomerRecordType: Identifiable {
    var id: String { rawValue }
}
