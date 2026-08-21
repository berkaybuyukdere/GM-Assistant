//
//  CustomerReservation.swift
//  GM Assistant
//
//  Whitelisted reservation summary returned by the
//  `customerResolveReservation` Cloud Function.
//

import Foundation
import CoreLocation

struct CustomerReservation: Codable, Equatable {
    var resKodu: String
    var franchiseId: String
    var aracId: String
    var aracPlaka: String
    var customerName: String?
    var checkoutAt: Date?
    var plannedReturnAt: Date?
    var pickUpBranch: String?
    var dropOffBranch: String?
    var vehicleMake: String?
    var vehicleModel: String?
    var roadsidePhone: String
    var officePhone: String?
    // Shuttle meeting point (from publicConfig.shuttleMeetingPoint, whitelisted by
    // customerResolveReservation). Optionals keep JSONDecoder compatibility with
    // previously persisted reservations — the silent re-resolve backfills them.
    var shuttleMeetingLat: Double?
    var shuttleMeetingLng: Double?
    var shuttleMeetingLabel: String?

    var shuttleMeetingCoordinate: CLLocationCoordinate2D? {
        guard let lat = shuttleMeetingLat, let lng = shuttleMeetingLng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var vehicleDisplayName: String {
        let name = [vehicleMake, vehicleModel]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name
    }

    /// Builds the model from the callable function's dictionary payload.
    init?(callableData: [String: Any]) {
        guard
            let res = callableData["resKodu"] as? String, !res.isEmpty,
            let fid = callableData["franchiseId"] as? String, !fid.isEmpty
        else { return nil }

        let isoParser = ISO8601DateFormatter()
        isoParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoParserPlain = ISO8601DateFormatter()

        func date(_ key: String) -> Date? {
            guard let s = callableData[key] as? String else { return nil }
            return isoParser.date(from: s) ?? isoParserPlain.date(from: s)
        }
        func str(_ key: String) -> String? {
            guard let s = (callableData[key] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !s.isEmpty else { return nil }
            return s
        }

        resKodu = res
        franchiseId = fid
        aracId = str("aracId") ?? ""
        aracPlaka = str("aracPlaka") ?? ""
        customerName = str("customerName")
        checkoutAt = date("checkoutAt")
        plannedReturnAt = date("plannedReturnAt")
        pickUpBranch = str("pickUpBranch")
        dropOffBranch = str("dropOffBranch")
        vehicleMake = str("vehicleMake")
        vehicleModel = str("vehicleModel")
        roadsidePhone = str("roadsidePhone") ?? "+41765373407"
        officePhone = str("officePhone")
        if let mp = callableData["shuttleMeetingPoint"] as? [String: Any],
           let lat = (mp["lat"] as? NSNumber)?.doubleValue,
           let lng = (mp["lng"] as? NSNumber)?.doubleValue,
           abs(lat) <= 90, abs(lng) <= 180 {
            shuttleMeetingLat = lat
            shuttleMeetingLng = lng
            let label = (mp["label"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            shuttleMeetingLabel = (label?.isEmpty == false) ? label : nil
        }
    }
}
