//
//  RemotePhotoGalleryView.swift
//  GM Assistant
//
//  Full-screen swipeable viewer for a submission's uploaded photo URLs —
//  lets the customer see, in place, exactly what was sent to the ERP.
//

import SwiftUI

struct RemotePhotoGallerySession: Identifiable {
    let id = UUID()
    let urls: [String]
    let startIndex: Int
}

struct RemotePhotoGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let session: RemotePhotoGallerySession
    @State private var index: Int

    init(session: RemotePhotoGallerySession) {
        self.session = session
        _index = State(initialValue: session.startIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(session.urls.enumerated()), id: \.offset) { i, url in
                    ZoomableAsyncPhoto(urlString: url)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: session.urls.count > 1 ? .always : .never))

            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding(16)
        }
    }
}

/// Simple pinch-to-zoom AsyncImage wrapper for the gallery pages.
private struct ZoomableAsyncPhoto: View {
    let urlString: String
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .empty:
                    ProgressView().tint(.white)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1, min(4, lastScale * value))
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                scale = 1
                                lastScale = 1
                            }
                        }
                case .failure:
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}
