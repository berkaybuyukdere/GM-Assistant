//
//  PhotoCaptureView.swift
//  GM Assistant
//
//  Photo picking (camera + library) and upload flow for one record
//  type. Uploads go to Storage, then a customerRecords doc is created
//  so staff see the photos live.
//

import SwiftUI
import PhotosUI

struct PhotoCaptureView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let reservation: CustomerReservation
    let type: CustomerRecordType

    @State private var images: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var uploading = false
    @State private var progress: Double = 0
    @State private var uploadFailed = false
    @State private var uploadDone = false

    private let maxPhotos = 20

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
                    if let image { images.append(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    for item in newItems {
                        if images.count >= maxPhotos { break }
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            images.append(image)
                        }
                    }
                    pickerItems = []
                }
            }
        }
        .interactiveDismissDisabled(uploading)
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    photoGrid
                    pickButtons
                    if uploadFailed {
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
                }
                .padding(18)
            }
            uploadBar
        }
    }

    // MARK: - Grid

    private var photoGrid: some View {
        Group {
            if images.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(GMTheme.textFaint)
                    Text("no_photos_yet").gmCaption(13)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .background(GMTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
                .gmBorder()
                .shadow(color: GMTheme.panelShadow, radius: 8, x: 0, y: 2)
            } else {
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Text("add_photos").gmSectionLabel()
                        Spacer()
                        Text(verbatim: "\(images.count) / \(maxPhotos)")
                            .font(GMTheme.ui(12.5, .medium))
                            .monospacedDigit()
                            .foregroundStyle(GMTheme.accentText)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 100), spacing: 9)],
                        spacing: 9
                    ) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 104, height: 104)
                                    .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))

                                if !uploading {
                                    Button {
                                        Haptics.light()
                                        images.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 19))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.black.opacity(0.45))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(5)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pickers

    private var pickButtons: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                showCamera = true
            } label: {
                Label("take_photo", systemImage: "camera.fill")
            }
            .buttonStyle(GMGhostButtonStyle(color: GMTheme.accentText, height: 46))
            .disabled(uploading || images.count >= maxPhotos)
            .opacity(uploading || images.count >= maxPhotos ? 0.45 : 1)

            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: maxPhotos - images.count,
                matching: .images
            ) {
                Label("choose_from_library", systemImage: "photo.stack.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GMTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(GMTheme.surfaceInset)
                    .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
                    .gmBorder(GMTheme.textSecondary.opacity(0.28), radius: GMTheme.radiusTight)
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
            .disabled(uploading || images.count >= maxPhotos)
            .opacity(uploading || images.count >= maxPhotos ? 0.45 : 1)
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
            .disabled(images.isEmpty || uploading)
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
        guard !images.isEmpty, !uploading else { return }
        uploading = true
        uploadFailed = false
        progress = 0
        Task {
            do {
                let urls = try await PhotoUploadService.upload(
                    images: images,
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
                print("Upload failed: \(error.localizedDescription)")
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
