//
//  PhotoCaptureView.swift
//  GM Assistant
//
//  Photo capture and upload for one record type.
//
//  Check-out and return are guided by a map rather than a list: a top-down
//  car with a marker everywhere a shot is needed. Standing at the marker's
//  position and pointing at the car is the whole instruction, which survives
//  translation better than any label.
//
//  Corners get their own markers because that is where parking damage lands,
//  each wheel gets its own, and the cabin takes as many photos as it needs.
//
//  The guide prompts, it does not gate — upload stays available with whatever
//  was taken and only notes what is still missing. Blocking a customer who
//  cannot reach the far side of the car in a tight garage would cost more
//  evidence than it gains.
//

import SwiftUI
import PhotosUI

struct PhotoCaptureView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let reservation: CustomerReservation
    let type: CustomerRecordType

    /// Named single shots, keyed by position on the car.
    @State private var slotImages: [PhotoAngle: UIImage] = [:]
    /// Sections that take any number of photos.
    @State private var collectionImages: [PhotoCollection: [UIImage]] = [:]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showLibrary = false
    /// Which marker or tile currently owns an open menu — the menu is a
    /// popover on that exact view, so it appears over what was tapped.
    @State private var openSlotMenu: PhotoAngle?
    @State private var openCollectionMenu: PhotoCollection?
    @State private var pickTarget: PickTarget?

    @State private var uploading = false
    @State private var progress: Double = 0
    @State private var uploadFailed = false
    @State private var uploadDone = false

    private enum PickTarget: Equatable {
        case slot(PhotoAngle)
        case collection(PhotoCollection)
    }

    // MARK: - Derived

    private var guide: [PhotoAngle] { PhotoAngle.guide(for: type) }
    private var isGuided: Bool { !guide.isEmpty }

    private var filledCount: Int { slotImages.count }
    private var missingCount: Int { max(0, guide.count - filledCount) }

    private func images(in collection: PhotoCollection) -> [UIImage] {
        collectionImages[collection] ?? []
    }

    private var totalPhotos: Int {
        filledCount + PhotoCollection.allCases.reduce(0) { $0 + images(in: $1).count }
    }

    private var canAddMore: Bool { totalPhotos < GMConfig.maxPhotosPerSubmission }

    /// Named slots in walk-around order, then the cabin, then extras — so the
    /// uploaded set reads in the order it was meant to be taken.
    private var uploadItems: [PhotoUploadItem] {
        var items = guide.compactMap { angle in
            slotImages[angle].map { PhotoUploadItem(image: $0, tag: angle.fileTag) }
        }
        for collection in PhotoCollection.allCases {
            for (index, image) in images(in: collection).enumerated() {
                items.append(PhotoUploadItem(
                    image: image,
                    tag: isGuided ? "\(collection.fileTag)-\(String(format: "%02d", index + 1))" : nil
                ))
            }
        }
        return items
    }

    private var titleKey: LocalizedStringKey {
        switch type {
        case .checkoutPhotos: return "checkout_photos"
        case .returnPhotos: return "return_photos"
        case .damagePhotos: return "damage_photos"
        case .shuttleRequest: return "shuttle_request"
        case .note: return "note"
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                GMCanvas()
                if uploadDone {
                    successView
                } else {
                    contentView
                }
            }
            .toolbarBackground(GMTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Capsule()
                            .fill(GMTheme.accent)
                            .frame(width: 3, height: 13)
                        Text(titleKey)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GMTheme.textPrimary)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Text("close")
                            .font(GMTheme.ui(13.5, .medium))
                            .foregroundStyle(GMTheme.textSecondary)
                    }
                    .disabled(uploading)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    if let image { accept(image) } else { pickTarget = nil }
                }
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $showLibrary,
                selection: $pickerItems,
                maxSelectionCount: librarySelectionLimit,
                matching: .images
            )
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task { await absorb(newItems) }
            }
        }
        .interactiveDismissDisabled(uploading)
    }

    private var librarySelectionLimit: Int {
        switch pickTarget {
        case .slot, .none:
            return 1
        case .collection:
            return max(1, GMConfig.maxPhotosPerSubmission - totalPhotos)
        }
    }

    // MARK: - Picking

    private func accept(_ image: UIImage) {
        switch pickTarget {
        case .slot(let angle):
            slotImages[angle] = image
            Haptics.capture()
        case .collection(let collection):
            guard canAddMore else { Haptics.warning(); return }
            collectionImages[collection, default: []].append(image)
            Haptics.capture()
        case .none:
            break
        }
        pickTarget = nil
    }

    private func absorb(_ items: [PhotosPickerItem]) async {
        let target = pickTarget
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            pickTarget = target
            accept(image)
            // A named slot takes exactly one image; a collection keeps going.
            if case .slot = target { break }
            if !canAddMore { break }
        }
        pickerItems = []
        pickTarget = nil
    }

    private func begin(_ target: PickTarget, camera: Bool) {
        Haptics.tap()
        pickTarget = target
        openSlotMenu = nil
        openCollectionMenu = nil
        // Let the popover finish dismissing before presenting the picker,
        // otherwise the two presentations collide and neither appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if camera { showCamera = true } else { showLibrary = true }
        }
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    if isGuided {
                        walkaroundPanel
                        cabinPanel
                    }
                    collectionPanel(.additional)
                    if uploadFailed { failureNote }
                }
                .padding(18)
            }
            uploadBar
        }
    }

    private var failureNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GMTheme.danger)
            Text("upload_failed")
                .font(GMTheme.ui(13))
                .foregroundStyle(GMTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GMTheme.danger.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
        .gmBorder(GMTheme.danger.opacity(0.22), radius: GMTheme.radiusTight)
    }

    // MARK: - Walk-around map

    private var walkaroundPanel: some View {
        GMPanel("walkaround", spacing: 12) {
            progressBar

            GeometryReader { proxy in
                ZStack {
                    CarDiagram()
                        .frame(
                            width: proxy.size.width * 0.40,
                            height: proxy.size.height * 0.74
                        )
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                    ForEach(PhotoAngle.mapped) { angle in
                        marker(angle, in: proxy.size)
                    }
                }
            }
            .frame(height: 360)

            Text("walkaround_hint")
                .gmCaption(11.5)
                .fixedSize(horizontal: false, vertical: true)
        } accessory: {
            Text(verbatim: "\(filledCount) / \(guide.count)")
                .font(GMTheme.ui(12.5, .semibold))
                .monospacedDigit()
                .foregroundStyle(missingCount == 0 ? GMTheme.accentText : GMTheme.textMuted)
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(GMTheme.surfaceRaised)
                Capsule()
                    .fill(GMTheme.accent)
                    .frame(
                        width: proxy.size.width
                            * (guide.isEmpty ? 0 : Double(filledCount) / Double(guide.count))
                    )
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.3), value: filledCount)
    }

    private func marker(_ angle: PhotoAngle, in size: CGSize) -> some View {
        let position = angle.mapPosition ?? UnitPoint(x: 0.5, y: 0.5)
        let diameter: CGFloat = angle.group == .wheels ? 32 : 38

        return Button {
            Haptics.select()
            openSlotMenu = angle
        } label: {
            ZStack {
                if let image = slotImages[angle] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                    Circle().strokeBorder(GMTheme.accent, lineWidth: 2.5)
                } else {
                    Circle().fill(GMTheme.surface)
                    Circle().strokeBorder(
                        GMTheme.accent.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3.5, 3])
                    )
                    Image(systemName: angle.icon)
                        .font(.system(size: diameter * 0.36, weight: .semibold))
                        .foregroundStyle(GMTheme.accent.opacity(0.85))
                }
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .popover(isPresented: slotMenuBinding(angle)) {
            slotMenu(angle)
        }
        .accessibilityLabel(Text(angle.labelKey))
        .position(x: position.x * size.width, y: position.y * size.height)
    }

    private func slotMenuBinding(_ angle: PhotoAngle) -> Binding<Bool> {
        Binding(
            get: { openSlotMenu == angle },
            set: { if !$0 && openSlotMenu == angle { openSlotMenu = nil } }
        )
    }

    private func slotMenu(_ angle: PhotoAngle) -> some View {
        captureMenu(
            title: angle.labelKey,
            hasPhoto: slotImages[angle] != nil,
            onCamera: { begin(.slot(angle), camera: true) },
            onLibrary: { begin(.slot(angle), camera: false) },
            onRemove: {
                Haptics.remove()
                slotImages[angle] = nil
                openSlotMenu = nil
            }
        )
    }

    /// Shared menu body for a marker or a tile. Rendered as a real popover so
    /// it points at the thing that was tapped rather than sliding up from the
    /// bottom of the screen.
    private func captureMenu(
        title: LocalizedStringKey,
        hasPhoto: Bool,
        onCamera: @escaping () -> Void,
        onLibrary: @escaping () -> Void,
        onRemove: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .gmSectionLabel(10)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            menuRow(
                titleKey: hasPhoto ? "retake" : "take_photo",
                icon: "camera.fill",
                action: onCamera
            )
            Rectangle().fill(GMTheme.divider).frame(height: GMTheme.hairline)
            menuRow(
                titleKey: "choose_from_library",
                icon: "photo.stack.fill",
                action: onLibrary
            )
            if hasPhoto, let onRemove {
                Rectangle().fill(GMTheme.divider).frame(height: GMTheme.hairline)
                menuRow(
                    titleKey: "remove",
                    icon: "trash.fill",
                    tint: GMTheme.danger,
                    action: onRemove
                )
            }
        }
        .frame(width: 228)
        .background(GMTheme.surface)
        .presentationCompactAdaptation(.popover)
    }

    private func menuRow(
        titleKey: LocalizedStringKey,
        icon: String,
        tint: Color = GMTheme.textPrimary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint == GMTheme.textPrimary ? GMTheme.accent : tint)
                    .frame(width: 20)
                Text(titleKey)
                    .font(GMTheme.ui(15))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cabin (dashboard slot + interior collection)

    private var cabinPanel: some View {
        GMPanel("cabin_label", spacing: 13) {
            HStack(spacing: 12) {
                slotTile(.dashboard)
                VStack(alignment: .leading, spacing: 4) {
                    Text(PhotoAngle.dashboard.labelKey)
                        .font(GMTheme.ui(14, .medium))
                        .foregroundStyle(GMTheme.textPrimary)
                    Text("angle_dashboard_hint")
                        .gmCaption(11.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Rectangle().fill(GMTheme.divider).frame(height: GMTheme.hairline)

            collectionBody(.interior)
        }
    }

    /// A named slot rendered as a tile, for shots that have no place on the map.
    private func slotTile(_ angle: PhotoAngle) -> some View {
        Button {
            Haptics.select()
            openSlotMenu = angle
        } label: {
            ZStack {
                if let image = slotImages[angle] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 84, height: 68)
                        .clipped()
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, GMTheme.accent)
                                .padding(4)
                        }
                } else {
                    RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                        .strokeBorder(GMTheme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .background(
                            RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                                .fill(GMTheme.surfaceInset)
                        )
                    Image(systemName: angle.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(GMTheme.accent.opacity(0.6))
                }
            }
            .frame(width: 84, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(uploading)
        .popover(isPresented: slotMenuBinding(angle)) { slotMenu(angle) }
        .accessibilityLabel(Text(angle.labelKey))
    }

    // MARK: - Collections

    private func collectionPanel(_ collection: PhotoCollection) -> some View {
        GMPanel(collection.labelKey, spacing: 11) {
            collectionBody(collection)
        } accessory: {
            if !images(in: collection).isEmpty {
                Text(verbatim: "\(images(in: collection).count)")
                    .font(GMTheme.ui(12.5, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(GMTheme.accentText)
            }
        }
    }

    private func collectionBody(_ collection: PhotoCollection) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            if images(in: collection).isEmpty {
                Text(collection.hintKey)
                    .gmCaption()
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 9)],
                spacing: 9
            ) {
                ForEach(Array(images(in: collection).enumerated()), id: \.offset) { index, image in
                    collectionTile(collection, image: image, index: index)
                }
                if canAddMore && !uploading {
                    addTile(collection)
                }
            }
        }
    }

    private func collectionTile(
        _ collection: PhotoCollection,
        image: UIImage,
        index: Int
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 92, height: 72)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
            if !uploading {
                Button {
                    Haptics.remove()
                    collectionImages[collection]?.remove(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.45))
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
    }

    private func addTile(_ collection: PhotoCollection) -> some View {
        Button {
            Haptics.select()
            openCollectionMenu = collection
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                    .strokeBorder(GMTheme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .background(
                        RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                            .fill(GMTheme.surfaceInset)
                    )
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(GMTheme.accent.opacity(0.75))
            }
            .frame(width: 92, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: Binding(
                get: { openCollectionMenu == collection },
                set: { if !$0 && openCollectionMenu == collection { openCollectionMenu = nil } }
            )
        ) {
            captureMenu(
                title: collection.labelKey,
                hasPhoto: false,
                onCamera: { begin(.collection(collection), camera: true) },
                onLibrary: { begin(.collection(collection), camera: false) },
                onRemove: nil
            )
        }
        .accessibilityLabel(Text("add_photo"))
    }

    // MARK: - Upload bar

    private var uploadBar: some View {
        VStack(spacing: 11) {
            if uploading {
                VStack(spacing: 7) {
                    HStack {
                        Text("uploading")
                            .font(GMTheme.ui(12.5, .medium))
                            .foregroundStyle(GMTheme.accentText)
                        Spacer()
                        Text(verbatim: "\(Int(progress * 100))%")
                            .font(GMTheme.ui(12.5, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(GMTheme.accentText)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(GMTheme.surfaceRaised)
                            Capsule()
                                .fill(GMTheme.accent)
                                .frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                }
            } else if isGuided && missingCount > 0 && totalPhotos > 0 {
                // Prompt, don't block.
                HStack(spacing: 7) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GMTheme.warning)
                    Text(String(format: String(localized: "shots_missing"), missingCount))
                        .font(GMTheme.ui(12.5))
                        .foregroundStyle(GMTheme.textMuted)
                    Spacer(minLength: 0)
                }
            }

            Button {
                upload()
            } label: {
                if uploading {
                    Text("uploading")
                } else {
                    Label("upload_photos", systemImage: "arrow.up.circle.fill")
                }
            }
            .buttonStyle(GMPrimaryButtonStyle())
            .disabled(totalPhotos == 0 || uploading)
        }
        .padding(18)
        .background(
            GMTheme.surface
                .overlay(alignment: .top) {
                    Rectangle().fill(GMTheme.border).frame(height: GMTheme.hairline)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(GMTheme.accentSoft)
                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(GMTheme.accent)
            }
            .frame(width: 76, height: 76)

            Text("upload_success")
                .font(GMTheme.ui(19, .semibold))
                .foregroundStyle(GMTheme.textPrimary)

            Text("upload_success_detail")
                .font(GMTheme.ui(14))
                .foregroundStyle(GMTheme.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Text("done")
            }
            .buttonStyle(GMPrimaryButtonStyle())
            .padding(.top, 8)
        }
        .padding(32)
    }

    private func upload() {
        let items = uploadItems
        guard !items.isEmpty, !uploading else { return }
        Haptics.tap()
        uploading = true
        uploadFailed = false
        progress = 0
        Task {
            do {
                let urls = try await PhotoUploadService.upload(
                    items: items,
                    reservation: reservation
                ) { value in
                    progress = value
                }
                try await appState.recordService?.addPhotoRecord(
                    type: type,
                    photoURLs: urls
                )
                uploadDone = true
                Haptics.success()
            } catch {
                GMLog.failure(GMLog.upload, "photo submission", error: error)
                uploadFailed = true
                Haptics.error()
            }
            uploading = false
        }
    }
}

/// Simple UIKit camera wrapper (front/back camera capture).
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera)
            ? .camera
            : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            parent.onCapture(image)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCapture(nil)
            parent.dismiss()
        }
    }
}
