//
//  ReservationHomeView.swift
//  GM Assistant
//
//  Reservation dashboard: vehicle + reservation cards, photo upload
//  actions (check-out / return), shuttle yes-no toggle,
//  roadside assistance + GM office call buttons, and the customer's
//  own submissions (live).
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
                GMTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        vehicleCard
                        reservationCard
                        photoActionsCard
                        noteCard
                        shuttleCard
                        assistanceCard
                        submissionsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("GM Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("change_reservation") {
                        Haptics.light()
                        appState.endSession()
                    }
                    .font(GMTheme.labelFont(13))
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

    // MARK: - Vehicle & reservation

    private var vehicleCard: some View {
        GMCard {
            HStack(spacing: 14) {
                GMIconBadge(systemName: "car.side.fill", size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    if !reservation.vehicleDisplayName.isEmpty {
                        Text(reservation.vehicleDisplayName)
                            .font(.system(size: 20, weight: .bold))
                    }
                    if !reservation.aracPlaka.isEmpty {
                        Text(reservation.aracPlaka)
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(GMTheme.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                Spacer()
            }
        }
    }

    private var reservationCard: some View {
        GMCard {
            HStack {
                Label {
                    Text(reservation.resKodu)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                } icon: {
                    Image(systemName: "number.square.fill")
                        .foregroundStyle(GMTheme.accent)
                }
                Spacer()
            }
            if let name = reservation.customerName {
                infoRow(labelKey: "customer", value: name)
            }
            if let checkoutAt = reservation.checkoutAt {
                infoRow(labelKey: "pickup_date", value: Self.dateFormatter.string(from: checkoutAt))
            }
            if let plannedReturn = reservation.plannedReturnAt {
                infoRow(labelKey: "planned_return", value: Self.dateFormatter.string(from: plannedReturn))
            }
            if let branch = reservation.pickUpBranch {
                infoRow(labelKey: "pickup_branch", value: branch)
            }
            if let branch = reservation.dropOffBranch {
                infoRow(labelKey: "dropoff_branch", value: branch)
            }
        }
    }

    private func infoRow(labelKey: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(labelKey)
                .font(GMTheme.labelFont(13))
                .foregroundStyle(GMTheme.textSecondary)
            Spacer()
            Text(value)
                .font(GMTheme.bodyFont(15))
                .multilineTextAlignment(.trailing)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    // MARK: - Photos

    private var photoActionsCard: some View {
        GMCard {
            Text("add_photos")
                .font(GMTheme.labelFont(13))
                .foregroundStyle(GMTheme.textSecondary)
                .textCase(.uppercase)
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
            HStack(spacing: 12) {
                GMIconBadge(systemName: icon, tint: tint, size: 38)
                Text(titleKey)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GMTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GMTheme.textSecondary)
            }
            .padding(14)
            .background(GMTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Note

    private var noteCard: some View {
        GMCard {
            HStack(spacing: 10) {
                GMIconBadge(systemName: "text.bubble.fill", size: 34)
                Text("write_a_note")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            TextField("note_placeholder", text: $noteText, axis: .vertical)
                .font(GMTheme.bodyFont(15))
                .lineLimit(2...4)
                .focused($noteFieldFocused)
                .padding(12)
                .background(GMTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                if noteSent {
                    Label("note_sent", systemImage: "checkmark.circle.fill")
                        .font(GMTheme.bodyFont(13))
                        .foregroundStyle(GMTheme.accent)
                        .transition(.opacity)
                } else if noteError {
                    Text("error_unknown")
                        .font(GMTheme.bodyFont(13))
                        .foregroundStyle(GMTheme.danger)
                }
                Spacer()
                Button {
                    sendNote()
                } label: {
                    if noteSaving {
                        ProgressView().tint(.white)
                    } else {
                        Label("send_note", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(GMPrimaryButtonStyle())
                .fixedSize()
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || noteSaving)
                .opacity(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
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

    private var shuttleCard: some View {
        GMCard {
            HStack(spacing: 10) {
                GMIconBadge(systemName: "bus.fill", size: 34)
                Text("shuttle_question")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                if shuttleSaving {
                    ProgressView()
                }
            }
            HStack(spacing: 10) {
                shuttleChoiceButton(titleKey: "yes", value: true)
                shuttleChoiceButton(titleKey: "no", value: false)
            }
            if let current = recordService?.shuttleRequested {
                Label {
                    Text(current ? "shuttle_requested_yes" : "shuttle_requested_no")
                } icon: {
                    Image(systemName: current ? "checkmark.circle.fill" : "xmark.circle.fill")
                }
                .font(GMTheme.bodyFont(13))
                .foregroundStyle(current ? GMTheme.accent : GMTheme.textSecondary)
            }
            // Live tracking — only when the request is YES; a listener failure
            // (expired session, network) degrades to the static confirmation.
            if recordService?.shuttleRequested == true,
               let tracking = shuttleTracking,
               !tracking.listenerFailed {
                shuttleLiveSection(tracking)
            }
            if shuttleError {
                Text("error_unknown")
                    .font(GMTheme.bodyFont(13))
                    .foregroundStyle(GMTheme.danger)
            }
        }
    }

    // MARK: - Live shuttle tracking UI

    @ViewBuilder
    private func shuttleLiveSection(_ tracking: ShuttleTrackingService) -> some View {
        if tracking.drivers.isEmpty {
            // No drivers sharing right now — calm placeholder, never an empty map.
            HStack(spacing: 10) {
                Image(systemName: "bus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GMTheme.textSecondary)
                Text("shuttle_no_driver_yet")
                    .font(GMTheme.bodyFont(13))
                    .foregroundStyle(GMTheme.textSecondary)
            }
            .padding(.top, 2)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                shuttleEtaHeadline(tracking)
                shuttleMiniMap(tracking)
                shuttleFreshnessCaption(tracking)
            }
            .padding(.top, 2)
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
                VStack(alignment: .leading, spacing: 4) {
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
                }
            } else {
                // All shared positions are older than 3 minutes — never show an ETA.
                Label("shuttle_location_unavailable", systemImage: "exclamationmark.circle")
                    .font(GMTheme.bodyFont(13))
                    .foregroundStyle(GMTheme.textSecondary)
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
                            Circle()
                                .fill(stale ? Color.gray : GMTheme.accent)
                            Image(systemName: "bus.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 34, height: 34)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    }
                }
            }
            if let mp = tracking.meetingPoint {
                Annotation(tracking.meetingLabel ?? String(localized: "shuttle_meeting_point"), coordinate: mp) {
                    Image(systemName: "flag.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white, GMTheme.danger)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                }
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // The mini-map is non-interactive (interactionModes: []); a tap opens the
        // full-screen, pannable map instead of fighting the card's scroll view.
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(7)
                .background(.black.opacity(0.35), in: Circle())
                .padding(8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .font(GMTheme.bodyFont(12))
                    .foregroundStyle(GMTheme.warning)
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
            Text(titleKey)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? .white : GMTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(isSelected ? GMTheme.accent : GMTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Assistance calls

    private var assistanceCard: some View {
        GMCard {
            Text("need_help")
                .font(GMTheme.labelFont(13))
                .foregroundStyle(GMTheme.textSecondary)
                .textCase(.uppercase)

            Button {
                Haptics.light()
                call(number: reservation.roadsidePhone)
            } label: {
                Label("roadside_assistance", systemImage: "wrench.and.screwdriver.fill")
            }
            .buttonStyle(GMPrimaryButtonStyle(color: GMTheme.danger))

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

    private var submissionsCard: some View {
        Group {
            if let records = recordService?.records, !records.isEmpty {
                GMCard {
                    HStack {
                        Text("my_submissions")
                            .font(GMTheme.labelFont(13))
                            .foregroundStyle(GMTheme.textSecondary)
                            .textCase(.uppercase)
                        Spacer()
                        Text("sent_to_erp")
                            .font(GMTheme.labelFont(11))
                            .foregroundStyle(GMTheme.accent)
                    }
                    ForEach(records) { record in
                        SubmissionRow(record: record) { startIndex in
                            gallerySession = RemotePhotoGallerySession(
                                urls: record.photos,
                                startIndex: startIndex
                            )
                        }
                        if record.id != records.last?.id {
                            Divider()
                        }
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
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
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
        Circle()
            .fill(GMTheme.accent.opacity(0.35))
            .frame(width: 34, height: 34)
            .scaleEffect(animating ? 1.9 : 0.9)
            .opacity(animating ? 0 : 0.6)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                GMIconBadge(systemName: icon, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(titleKey)
                        .font(.system(size: 15, weight: .semibold))
                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(GMTheme.bodyFont(12))
                        .foregroundStyle(GMTheme.textSecondary)
                }
                Spacer()
                Image(systemName: record.status == "seen" ? "checkmark.circle.fill" : "paperplane.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(record.status == "seen" ? GMTheme.accent : GMTheme.textSecondary)
            }

            if record.type == .note, let note = record.note, !note.isEmpty {
                Text(note)
                    .font(GMTheme.bodyFont(14))
                    .foregroundStyle(GMTheme.textPrimary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GMTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if !record.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
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
                                            .foregroundStyle(GMTheme.textSecondary)
                                    default:
                                        ProgressView()
                                    }
                                }
                                .frame(width: 72, height: 72)
                                .background(GMTheme.background)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

extension CustomerRecordType: Identifiable {
    var id: String { rawValue }
}
