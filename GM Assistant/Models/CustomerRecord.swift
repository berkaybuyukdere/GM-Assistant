//
//  CustomerRecord.swift
//  GM Assistant
//
//  A single customer submission stored at
//  franchises/{franchiseId}/customerRecords/{id} — photos for
//  check-out / return / damage, a shuttle request, or a note.
//  Mirrored by the staff app's Customer Records section.
//

import Foundation
import FirebaseFirestore

enum CustomerRecordType: String, Codable, CaseIterable {
    case checkoutPhotos = "checkout_photos"
    case returnPhotos = "return_photos"
    case damagePhotos = "damage_photos"
    case shuttleRequest = "shuttle_request"
    case note = "note"
}

struct CustomerRecord: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var franchiseId: String
    var resKodu: String
    var aracId: String
    var aracPlaka: String
    var customerUid: String
    var customerName: String?
    var type: CustomerRecordType
    var photos: [String]
    var note: String?
    var shuttleRequested: Bool?
    var createdAt: Date
    var updatedAt: Date
    var status: String

    static func newRecord(
        reservation: CustomerReservation,
        customerUid: String,
        type: CustomerRecordType,
        photos: [String] = [],
        note: String? = nil,
        shuttleRequested: Bool? = nil
    ) -> CustomerRecord {
        CustomerRecord(
            franchiseId: reservation.franchiseId,
            resKodu: reservation.resKodu,
            aracId: reservation.aracId,
            aracPlaka: reservation.aracPlaka,
            customerUid: customerUid,
            customerName: reservation.customerName,
            type: type,
            photos: photos,
            note: note,
            shuttleRequested: shuttleRequested,
            createdAt: Date(),
            updatedAt: Date(),
            status: "new"
        )
    }
}
