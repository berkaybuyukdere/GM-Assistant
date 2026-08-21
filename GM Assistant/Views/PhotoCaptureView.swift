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
                GMTheme.background.ignoresSafeArea()
                if uploadDone {
                    successView
                } else {
                    contentView
                }
            }
            .navigationTitle(Text(titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("close") { dismiss() }
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
                VStack(spacing: 16) {
                    photoGrid
                    pickButtons
                    if uploadFailed {
                        Label {
                            Text("upload_failed")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(GMTheme.bodyFont(14))
                        .foregroundStyle(GMTheme.danger)
                    }
                }
                .padding(16)
            }
            uploadBar
        }
    }

    private var photoGrid: some View {
        Group {
            if images.isEmpty {
                GMCard {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 40))
                                .foregroundStyle(GMTheme.textSecondary)
                            Text("no_photos_yet")
                                .font(GMTheme.bodyFont(14))
                                .foregroundStyle(GMTheme.textSecondary)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            if !uploading {
                                Button {
                                    Haptics.light()
                                    images.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.white, GMTheme.danger)
                                }
                                .padding(4)
                            }
                        }
                    }
                }
            }
        }
    }

    private var pickButtons: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.light()
                showCamera = true
            } label: {
                Label("take_photo", systemImage: "camera.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(GMTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(uploading || images.count >= maxPhotos)

            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: maxPhotos - images.count,
                matching: .images
            ) {
                Label("choose_from_library", systemImage: "photo.stack.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(GMTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
            .disabled(uploading || images.count >= maxPhotos)
        }
    }

    private var uploadBar: some View {
        VStack(spacing: 10) {
            if uploading {
                ProgressView(value: progress)
                    .tint(GMTheme.accent)
            }
            Button {
                Haptics.light()
                upload()
            } label: {
                if uploading {
                    HStack(spacing: 6) {
                        Text("uploading")
                        Text(verbatim: "\(Int(progress * 100))%")
                    }
                } else {
                    Label("upload_photos", systemImage: "icloud.and.arrow.up.fill")
                }
            }
            .buttonStyle(GMPrimaryButtonStyle())
            .disabled(images.isEmpty || uploading)
            .opacity(images.isEmpty || uploading ? 0.6 : 1)
        }
        .padding(16)
        .background(GMTheme.card)
    }

    private var successView: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 70))
                .foregroundStyle(GMTheme.accent)
            Text("upload_success")
                .font(GMTheme.titleFont(22))
            Text("upload_success_detail")
                .font(GMTheme.bodyFont(15))
                .foregroundStyle(GMTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                dismiss()
            } label: {
                Text("done")
            }
            .buttonStyle(GMPrimaryButtonStyle())
            .padding(.top, 8)
        }
        .padding(28)
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
