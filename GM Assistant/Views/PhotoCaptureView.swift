//
//  PhotoCaptureView.swift
//  GM Assistant
//
//  Photo capture and upload for one record type.
//
//  Check-out and return are guided: the screen shows the walk-around as a
//  set of named slots the customer fills, rather than a bare picker. The
//  guide prompts, it does not gate — upload stays available with whatever
//  has been taken, and only warns about what is still missing. Blocking a
//  customer who cannot reach the far side of the car in a tight garage
//  would cost more evidence than it gains.
//
//  Other record types keep the free-form grid.
//

import SwiftUI
import PhotosUI

struct PhotoCaptureView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let reservation: CustomerReservation
    let type: CustomerRecordType

    /// Named walk-around shots, keyed by angle.
    @State private var slotImages: [PhotoAngle: UIImage] = [:]
    /// Anything beyond the guide (close-ups, extra detail).
    @State private var extraImages: [UIImage] = []

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showAddSource = false
    @State private var showManage = false
    /// Which slot the next picked image fills; `nil` means the extras section.
    @State private var targetAngle: PhotoAngle?
    @State private var manageAngle: PhotoAngle?

    @State private var uploading = false
    @State private var progress: Double = 0
    @State private var uploadFailed = false
    @State private var uploadDone = false

    private var guide: [PhotoAngle] { PhotoAngle.guide(for: type) }
    private var isGuided: Bool { !guide.isEmpty }

    private var filledCount: Int { slotImages.count }
    private var missingCount: Int { max(0, guide.count - filledCount) }
    private var totalPhotos: Int { filledCount + extraImages.count }
    private var canAddMore: Bool { totalPhotos < GMConfig.maxPhotosPerSubmission }

    /// Guide shots in walk-around order first, then extras — so the uploaded
    /// set reads in the order it was meant to be taken.
    private var uploadItems: [PhotoUploadItem] {
        var items = guide.compactMap { angle in
            slotImages[angle].map { PhotoUploadItem(image: $0, tag: angle.fileTag) }
        }
        items += extraImages.map { PhotoUploadItem(image: $0, tag: isGuided ? "99-extra" : nil) }
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
                    if let image { accept(image) } else { targetAngle = nil }
                }
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $showLibrary,
                selection: $pickerItems,
                maxSelectionCount: targetAngle == nil
                    ? max(1, GMConfig.maxPhotosPerSubmission - totalPhotos)
                    : 1,
                matching: .images
            )
            .confirmationDialog("add_photo", isPresented: $showAddSource, titleVisibility: .visible) {
                Button("take_photo") { showCamera = true }
                Button("choose_from_library") { showLibrary = true }
                Button("cancel", role: .cancel) { targetAngle = nil }
            }
            .confirmationDialog("photo_options", isPresented: $showManage, titleVisibility: .visible) {
                Button("retake") {
                    targetAngle = manageAngle
                    showAddSource = true
                }
                Button("remove", role: .destructive) {
                    if let manageAngle { slotImages[manageAngle] = nil }
                    manageAngle = nil
                }
                Button("cancel", role: .cancel) { manageAngle = nil }
            }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task { await absorb(newItems) }
            }
        }
        .interactiveDismissDisabled(uploading)
    }

    // MARK: - Picking

    private func accept(_ image: UIImage) {
        if let angle = targetAngle {
            slotImages[angle] = image
        } else if canAddMore {
            extraImages.append(image)
        }
        targetAngle = nil
    }

    private func absorb(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            accept(image)
            // A slot takes exactly one image; extras keep consuming.
            if targetAngle == nil && !canAddMore { break }
        }
        pickerItems = []
        targetAngle = nil
    }

    private func beginAdd(for angle: PhotoAngle?) {
        Haptics.light()
        targetAngle = angle
        showAddSource = true
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    if isGuided {
                        walkaroundPanel
                        extrasPanel
                    } else {
                        freeFormPanel
                    }
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

    // MARK: - Guided walk-around

    private var walkaroundPanel: some View {
        GMPanel("walkaround", spacing: 13) {
            progressBar

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 9)],
                spacing: 9
            ) {
                ForEach(guide) { angle in
                    slotTile(angle)
                }
            }
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
        .animation(.easeOut(duration: 0.25), value: filledCount)
    }

    private func slotTile(_ angle: PhotoAngle) -> some View {
        Button {
            if slotImages[angle] != nil {
                Haptics.light()
                manageAngle = angle
                showManage = true
            } else {
                beginAdd(for: angle)
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if let image = slotImages[angle] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 76)
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
                            .strokeBorder(
                                GMTheme.borderStrong,
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                            .background(
                                RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                                    .fill(GMTheme.surfaceInset)
                            )
                            .frame(width: 96, height: 76)
                        Image(systemName: angle.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(GMTheme.accent.opacity(0.55))
                    }
                }
                .frame(width: 96, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))

                Text(angle.labelKey)
                    .font(GMTheme.ui(11, .medium))
                    .foregroundStyle(
                        slotImages[angle] != nil ? GMTheme.textPrimary : GMTheme.textMuted
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(uploading)
    }

    // MARK: - Extras

    private var extrasPanel: some View {
        GMPanel("additional_photos", spacing: 11) {
            if extraImages.isEmpty {
                Text("additional_photos_hint")
                    .gmCaption()
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 9)],
                spacing: 9
            ) {
                ForEach(Array(extraImages.enumerated()), id: \.offset) { index, image in
                    extraTile(image: image, index: index)
                }
                if canAddMore && !uploading {
                    addExtraTile
                }
            }
        }
    }

    private func extraTile(image: UIImage, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 76)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
            if !uploading {
                Button {
                    Haptics.light()
                    extraImages.remove(at: index)
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

    private var addExtraTile: some View {
        Button {
            beginAdd(for: nil)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                    .strokeBorder(
                        GMTheme.borderStrong,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                            .fill(GMTheme.surfaceInset)
                    )
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(GMTheme.accent.opacity(0.7))
            }
            .frame(width: 96, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Free-form (non-guided types)

    private var freeFormPanel: some View {
        Group {
            if extraImages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(GMTheme.textFaint)
                    Text("no_photos_yet").gmCaption(13)
                    Button {
                        beginAdd(for: nil)
                    } label: {
                        Label("add_photo", systemImage: "plus")
                    }
                    .buttonStyle(GMGhostButtonStyle(color: GMTheme.accentText, height: 42))
                    .frame(width: 190)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(GMTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
                .gmBorder()
                .shadow(color: GMTheme.panelShadow, radius: 8, x: 0, y: 2)
            } else {
                GMPanel("add_photos", spacing: 11) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 96), spacing: 9)],
                        spacing: 9
                    ) {
                        ForEach(Array(extraImages.enumerated()), id: \.offset) { index, image in
                            extraTile(image: image, index: index)
                        }
                        if canAddMore && !uploading {
                            addExtraTile
                        }
                    }
                } accessory: {
                    Text(verbatim: "\(extraImages.count) / \(GMConfig.maxPhotosPerSubmission)")
                        .font(GMTheme.ui(12.5, .medium))
                        .monospacedDigit()
                        .foregroundStyle(GMTheme.textMuted)
                }
            }
        }
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
                Haptics.light()
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
