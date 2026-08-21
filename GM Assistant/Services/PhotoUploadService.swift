//
//  PhotoUploadService.swift
//  GM Assistant
//
//  Uploads customer photos to Storage at
//  customer_records/{franchiseId}/{resKodu}/{uid}/{fileName}
//  (path enforced by storage.rules) and returns download URLs.
//
//  Uploads run concurrently (bounded) instead of one-at-a-time — with
//  several photos, sequential upload was the main source of the long
//  wait customers felt in the photo screen.
//
//  Each item may carry a `tag` (see `PhotoAngle.fileTag`) which is written
//  into the file name, so a guided walk-around arrives at the backend
//  self-describing without changing the document shape.
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseStorage

/// One photo queued for upload, optionally labelled with the shot it fills.
struct PhotoUploadItem {
    let image: UIImage
    /// File-name tag such as `01-front`; `nil` for free-form extras.
    var tag: String?

    init(image: UIImage, tag: String? = nil) {
        self.image = image
        self.tag = tag
    }
}

enum PhotoUploadService {
    enum UploadError: Error {
        case notSignedIn
        case encodingFailed
    }

    private static let maxConcurrentUploads = 4

    /// Uploads items with bounded concurrency, reporting 0…1 progress as
    /// each finishes. Result order matches the input order.
    static func upload(
        items: [PhotoUploadItem],
        reservation: CustomerReservation,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> [String] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw UploadError.notSignedIn
        }
        let total = items.count
        guard total > 0 else { return [] }

        let safeRes = reservation.resKodu
            .replacingOccurrences(of: "/", with: "_")
        let folder = Storage.storage().reference()
            .child("customer_records")
            .child(reservation.franchiseId)
            .child(safeRes)
            .child(uid)

        var results = [String?](repeating: nil, count: total)
        let completed = CompletedCounter()

        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            var nextIndex = 0

            func scheduleNext() {
                guard nextIndex < total else { return }
                let index = nextIndex
                nextIndex += 1
                let item = items[index]
                group.addTask {
                    let url = try await uploadOne(item, into: folder)
                    return (index, url)
                }
            }

            for _ in 0..<min(maxConcurrentUploads, total) {
                scheduleNext()
            }
            while let (index, urlString) = try await group.next() {
                results[index] = urlString
                let done = await completed.increment()
                await progress(Double(done) / Double(total))
                scheduleNext()
            }
        }

        return results.compactMap { $0 }
    }

    /// Convenience for unlabelled uploads.
    static func upload(
        images: [UIImage],
        reservation: CustomerReservation,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> [String] {
        try await upload(
            items: images.map { PhotoUploadItem(image: $0) },
            reservation: reservation,
            progress: progress
        )
    }

    private static func uploadOne(
        _ item: PhotoUploadItem,
        into folder: StorageReference
    ) async throws -> String {
        // Compress once, outside the retry, so a network retry does not pay
        // for re-encoding the image.
        guard let data = compressed(item.image) else {
            throw UploadError.encodingFailed
        }
        let unique = UUID().uuidString.uppercased()
        let name = item.tag.map { "\($0)-\(unique).jpg" } ?? "\(unique).jpg"
        let ref = folder.child(name)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        return try await GMRetry.run(
            context: "photo upload",
            logger: GMLog.upload
        ) {
            _ = try await ref.putDataAsync(data, metadata: metadata)
            let url = try await ref.downloadURL()
            return url.absoluteString
        }
    }

    /// JPEG-encodes under the 10 MB storage rule limit, downscaling
    /// very large captures first.
    private static func compressed(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 2200
        var working = image
        let largest = max(image.size.width, image.size.height)
        if largest > maxDimension {
            let scale = maxDimension / largest
            let newSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            let renderer = UIGraphicsImageRenderer(size: newSize)
            working = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
        for quality in [0.7, 0.5, 0.35] {
            if let data = working.jpegData(compressionQuality: quality),
               data.count < 9_500_000 {
                return data
            }
        }
        return working.jpegData(compressionQuality: 0.2)
    }
}

/// Thread-safe completed-count for progress reporting across concurrent uploads.
private actor CompletedCounter {
    private var count = 0

    func increment() -> Int {
        count += 1
        return count
    }
}
