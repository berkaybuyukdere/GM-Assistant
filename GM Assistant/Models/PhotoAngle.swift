//
//  PhotoAngle.swift
//  GM Assistant
//
//  The shot list for a check-out or return walk-around.
//
//  Photo evidence is the reason this app exists: a timestamped set taken by
//  the customer is what settles "was that scratch already there?". A free
//  photo picker produced whatever the customer thought to take, which is
//  usually three angles of the same corner. Naming the shots turns the
//  screen into a checklist and makes the resulting set comparable between
//  hand-over and hand-back.
//
//  The chosen angle travels to the backend in the Storage file name
//  (`01-front-<uuid>.jpg`). That needs no schema change and no security-rule
//  change — the customer_records storage rule leaves the file name free —
//  so staff reading the URL can see which shot is which, and nothing about
//  the existing document shape moves.
//

import SwiftUI

enum PhotoAngle: String, CaseIterable, Identifiable, Equatable {
    case front
    case rear
    case left
    case right
    case wheels
    case interior
    case dashboard

    var id: String { rawValue }

    /// Position in the walk-around, 1-based — also the file-name prefix, so
    /// an alphabetical listing of the folder is in walk-around order.
    var order: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    /// `01-front` — stable, lowercase, safe in a Storage path.
    var fileTag: String {
        String(format: "%02d-%@", order, rawValue)
    }

    var labelKey: LocalizedStringKey {
        switch self {
        case .front: return "angle_front"
        case .rear: return "angle_rear"
        case .left: return "angle_left"
        case .right: return "angle_right"
        case .wheels: return "angle_wheels"
        case .interior: return "angle_interior"
        case .dashboard: return "angle_dashboard"
        }
    }

    var icon: String {
        switch self {
        case .front: return "arrow.up.circle.fill"
        case .rear: return "arrow.down.circle.fill"
        case .left: return "arrow.left.circle.fill"
        case .right: return "arrow.right.circle.fill"
        case .wheels: return "circle.dashed"
        case .interior: return "carseat.left.fill"
        case .dashboard: return "speedometer"
        }
    }

    /// The guided shot list for a record type. Check-out and return are the
    /// two moments that get compared against each other, so they share one
    /// list; everything else stays free-form.
    static func guide(for type: CustomerRecordType) -> [PhotoAngle] {
        switch type {
        case .checkoutPhotos, .returnPhotos:
            return allCases
        case .damagePhotos, .shuttleRequest, .note:
            return []
        }
    }
}
