//
//  CustomerRecordService.swift
//  GM Assistant
//
//  Live Firestore access to the customer's own submissions at
//  franchises/{franchiseId}/customerRecords. Security rules restrict
//  reads/writes to docs whose customerUid matches the anonymous uid
//  and whose RES code matches the registered customer session.
//

import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

@Observable
@MainActor
final class CustomerRecordService {
    private(set) var records: [CustomerRecord] = []
    private(set) var shuttleRequested: Bool?

    private var reservation: CustomerReservation
    private var listener: ListenerRegistration?

    init(reservation: CustomerReservation) {
        self.reservation = reservation
    }

    private var uid: String? { Auth.auth().currentUser?.uid }

    private var collection: CollectionReference {
        Firestore.firestore()
            .collection("franchises")
            .document(reservation.franchiseId)
            .collection("customerRecords")
    }

    func update(reservation: CustomerReservation) {
        let franchiseChanged = reservation.franchiseId != self.reservation.franchiseId
        let resChanged = reservation.resKodu != self.reservation.resKodu
        self.reservation = reservation
        if franchiseChanged || resChanged {
            stop()
            start()
        }
    }

    func start() {
        guard listener == nil, let uid else { return }
        listener = collection
            .whereField("customerUid", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    print("customerRecords listener: \(error.localizedDescription)")
                    return
                }
                let fetched: [CustomerRecord] = (snapshot?.documents ?? [])
                    .compactMap { try? $0.data(as: CustomerRecord.self) }
                Task { @MainActor in
                    self.records = fetched.filter { $0.type != .shuttleRequest }
                    self.shuttleRequested = fetched
                        .first { $0.type == .shuttleRequest }?
                        .shuttleRequested
                }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        records = []
        shuttleRequested = nil
    }

    /// Creates a photo submission record (check-out / return / damage).
    func addPhotoRecord(type: CustomerRecordType, photoURLs: [String]) async throws {
        guard let uid, !photoURLs.isEmpty else { return }
        let record = CustomerRecord.newRecord(
            reservation: reservation,
            customerUid: uid,
            type: type,
            photos: photoURLs
        )
        try collection.document(UUID().uuidString.uppercased())
            .setData(from: record)
    }

    /// Sends a free-text note — appears live in the staff app's Customer
    /// Records section for this reservation.
    func addNote(text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid, !trimmed.isEmpty else { return }
        let record = CustomerRecord.newRecord(
            reservation: reservation,
            customerUid: uid,
            type: .note,
            note: trimmed
        )
        try collection.document(UUID().uuidString.uppercased())
            .setData(from: record)
    }

    /// Upserts the single shuttle-request record for this customer (live
    /// yes/no toggle; staff sees the change immediately).
    func setShuttleRequested(_ requested: Bool) async throws {
        guard let uid else { return }
        shuttleRequested = requested // optimistic; listener confirms
        let docId = "SHUTTLE_\(uid)_\(reservation.resKodu)"
            .replacingOccurrences(of: "/", with: "_")
        let ref = collection.document(docId)
        let existing = try? await ref.getDocument()
        if existing?.exists == true {
            try await ref.updateData([
                "shuttleRequested": requested,
                "updatedAt": Timestamp(date: Date()),
                "status": "new",
            ])
        } else {
            let record = CustomerRecord.newRecord(
                reservation: reservation,
                customerUid: uid,
                type: .shuttleRequest,
                shuttleRequested: requested
            )
            try ref.setData(from: record)
        }
    }
}
