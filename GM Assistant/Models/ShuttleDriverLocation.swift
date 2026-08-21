//
//  ShuttleDriverLocation.swift
//  GM Assistant
//
//  Customer-side view of a live shuttle driver position published by the
//  staff app to franchises/{franchiseId}/shuttleDriverLocations. Customers
//  only ever see actively sharing drivers (isSharing == true) — never
//  offline "ghost" pins.
//

import Foundation
import CoreLocation
import FirebaseFirestore

struct ShuttleDriverLocation: Identifiable, Equatable {
    let id: String
    let driverName: String
    let latitude: Double
    let longitude: Double
    let updatedAt: Date
    let speedMps: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Age of the last position write (clamped ≥ 0 to tolerate clock skew).
    var secondsSinceUpdate: TimeInterval {
        secondsSinceUpdate(asOf: Date())
    }

    /// Age of the last write measured against an explicit clock. Views drive
    /// this from a `TimelineView` tick so freshness updates every second even
    /// when no new Firestore write has arrived.
    func secondsSinceUpdate(asOf now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(updatedAt))
    }

    /// No write for >90 s — show the grey/weak-signal state.
    var isStale: Bool { isStale(asOf: Date()) }
    func isStale(asOf now: Date) -> Bool { secondsSinceUpdate(asOf: now) > 90 }

    /// No write for >180 s — hide the ETA entirely (never show ancient data).
    var isExpired: Bool { isExpired(asOf: Date()) }
    func isExpired(asOf now: Date) -> Bool { secondsSinceUpdate(asOf: now) > 180 }

    /// Compact, language-neutral "45s" / "3 min" age string for the freshness caption.
    static func ageText(seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m) min" }
        return "\(m / 60)h \(m % 60)m"
    }

    /// Defensive Firestore parser (mirrors the staff app's parser, simplified).
    /// Requires driverUid + coordinates + isSharing == true; tolerates a missing
    /// updatedAt by treating the doc as already expired instead of crashing.
    static func from(document: QueryDocumentSnapshot) -> ShuttleDriverLocation? {
        let data = document.data()
        guard let uid = data["driverUid"] as? String, !uid.isEmpty,
              let lat = (data["latitude"] as? NSNumber)?.doubleValue,
              let lng = (data["longitude"] as? NSNumber)?.doubleValue,
              abs(lat) <= 90, abs(lng) <= 180,
              (data["isSharing"] as? Bool) == true else { return nil }
        let name = ((data["driverName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Shuttle"
        let updated: Date
        if let ts = data["updatedAt"] as? Timestamp {
            updated = ts.dateValue()
        } else {
            // Missing timestamp → treat as long-stale, not fresh.
            updated = Date.distantPast
        }
        return ShuttleDriverLocation(
            id: document.documentID,
            driverName: name,
            latitude: lat,
            longitude: lng,
            updatedAt: updated,
            speedMps: (data["speedMps"] as? NSNumber)?.doubleValue
        )
    }
}
