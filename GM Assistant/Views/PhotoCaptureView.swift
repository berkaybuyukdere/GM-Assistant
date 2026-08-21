//
//  PhotoCaptureView.swift
//  GM Assistant
//
//  Photo picking (camera + library) and upload flow for one record
//  type. Uploads go to Storage, then a customerRecords doc is created
//  so staff see the photos live.
//
//  Presented as a capture queue: a counter strip, an indexed grid, and a
//  fixed transmit bar at the bottom.
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
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        Rectangle()
                            .fill(GMTheme.accent)
                            .frame(width: 2, height: 12)
                        Text(titleKey)
                            .font(.system(size: 11.5, weight: .bold))
                            .tracking(1.1)
                            .textCase(.uppercase)
                            .foregroundStyle(GMTheme.textPrimary)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("close").gmMicroLabel(9.5, color: GMTheme.textSecondary)
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
                VStack(spacing: 12) {
                    queueStrip
                    photoGrid
                    pickButtons
                    if uploadFailed {
                        HStack(alignment: .top, spacing: 9) {
                            Rectangle()
                                .fill(GMTheme.danger)
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: "FAULT").gmMicroLabel(8.5, color: GMTheme.danger)
                                Text("upload_failed")
                                    .font(GMTheme.ui(12.5))
                                    .foregroundStyle(GMTheme.textSecondary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GMTheme.danger.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
                        .gmBorder(GMTheme.danger.opacity(0.28), radius: GMTheme.radiusTight)
                    }
                }
                .padding(16)
            }
            uploadBar
        }
    }

    // MARK: - Queue strip

    private var queueStrip: some View {
        HStack(spacing: 9) {
            GMStatusDot(
                color: images.isEmpty ? GMTheme.textFaint : GMTheme.accent,
                size: 6
            )
            Text(verbatim: "CAPTURE QUEUE")
                .gmMicroLabel(9, color: GMTheme.textSecondary)
            Spacer(minLength: 8)
            Text(verbatim: "\(images.count) / \(maxPhotos)")
                .font(GMTheme.mono(11, .semibold))
                .foregroundStyle(images.isEmpty ? GMTheme.textFaint : GMTheme.accentBright)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(GMTheme.surface.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
        .gmBorder()
        .animation(.easeOut(duration: 0.15), value: images.count)
    }

    // MARK: - Grid

    private var photoGrid: some View {
        Group {
            if images.isEmpty {
                VStack(spacing: 11) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(GMTheme.textFaint)
                    Text("no_photos_yet")
                        .gmMicroLabel(9.5, color: GMTheme.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
                .background(GMTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
                .gmBorder()
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 104, height: 104)
                                .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
                                .gmBorder(GMTheme.border, radius: GMTheme.radiusTight)
                                .overlay(alignment: .bottomLeading) {
                                    Text(verbatim: String(format: "%02d", index + 1))
                                        .font(GMTheme.mono(9, .bold))
                                        .foregroundStyle(GMTheme.accentBright)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(GMTheme.background.opacity(0.85))
                                        .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
                                        .padding(5)
                                }

                            if !uploading {
                                Button {
                                    Haptics.light()
                                    images.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundStyle(GMTheme.textPrimary)
                                        .frame(width: 20, height: 20)
                                        .background(GMTheme.background.opacity(0.9))
                                        .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
                                        .gmBorder(GMTheme.borderStrong, radius: 1)
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

    // MARK: - Pickers

    private var pickButtons: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                showCamera = true
            } label: {
                Label("take_photo", systemImage: "camera.fill")
            }
            .buttonStyle(GMGhostButtonStyle(color: GMTheme.accentBright, height: 44))
            .disabled(uploading || images.count >= maxPhotos)
            .opacity(uploading || images.count >= maxPhotos ? 0.35 : 1)

            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: maxPhotos - images.count,
                matching: .images
            ) {
                Label("choose_from_library", systemImage: "photo.stack.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(GMTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(GMTheme.surfaceInset)
                    .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
                    .gmBorder(GMTheme.textSecondary.opacity(0.35))
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
            .disabled(uploading || images.count >= maxPhotos)
            .opacity(uploading || images.count >= maxPhotos ? 0.35 : 1)
        }
    }

    // MARK: - Transmit bar

    private var uploadBar: some View {
        VStack(spacing: 10) {
            if uploading {
                VStack(spacing: 6) {
                    HStack {
                        Text(verbatim: "TRANSMITTING").gmMicroLabel(8.5, color: GMTheme.accentBright)
                        Spacer()
                        Text(verbatim: "\(Int(progress * 100))%")
                            .font(GMTheme.mono(10, .bold))
                            .foregroundStyle(GMTheme.accentBright)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(GMTheme.surfaceInset)
                            Rectangle()
                                .fill(GMTheme.accent)
                                .frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
                }
            }

            Button {
                Haptics.light()
                upload()
            } label: {
                if uploading {
                    Text("uploading")
                } else {
                    Label("upload_photos", systemImage: "arrow.up.to.line")
                }
            }
            .buttonStyle(GMPrimaryButtonStyle())
            .disabled(images.isEmpty || uploading)
        }
        .padding(16)
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
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous)
                    .fill(GMTheme.accentWash)
                RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous)
                    .strokeBorder(GMTheme.accent.opacity(0.5), lineWidth: GMTheme.hairline)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(GMTheme.accentBright)
            }
            .frame(width: 68, height: 68)

            Text("upload_success")
                .font(.system(size: 15, weight: .bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(GMTheme.textPrimary)

            Text("upload_success_detail")
                .font(GMTheme.ui(12.5))
                .foregroundStyle(GMTheme.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                dismiss()
            } label: {
                Text("done")
            }
            .buttonStyle(GMPrimaryButtonStyle())
            .padding(.top, 6)
        }
        .padding(30)
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
