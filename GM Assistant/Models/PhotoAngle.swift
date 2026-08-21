//
//  PhotoAngle.swift
//  GM Assistant
//
//  The shot list for a check-out or return walk-around, and where each shot
//  sits on the car diagram.
//
//  Photo evidence is the reason this app exists: a timestamped set taken by
//  the customer is what settles "was that scratch already there?". Naming
//  the shots and placing them around a top-down car turns the screen into a
//  map of where to stand, which is far easier to follow than a list.
//
//  Corners matter as much as flat sides — most parking damage lands on a
//  bumper corner, which a straight-on front or side shot flattens out of
//  view. And a car has four wheels, so it gets four wheel slots rather than
//  one that quietly stands in for all of them.
//
//  The chosen shot travels to the backend in the Storage file name
//  (`01-front-<uuid>.jpg`). That needs no schema change and no security-rule
//  change — the customerRecords create rule uses hasAll() rather than a
//  strict field allowlist, and the storage rule leaves the file name free.
//

import SwiftUI

/// One named, single-photo slot.
enum PhotoAngle: String, CaseIterable, Identifiable, Equatable {
    // Exterior, clockwise from the nose.
    case front
    case frontRight
    case right
    case rearRight
    case rear
    case rearLeft
    case left
    case frontLeft
    // One per wheel.
    case wheelFrontLeft
    case wheelFrontRight
    case wheelRearLeft
    case wheelRearRight
    // Cabin.
    case dashboard

    var id: String { rawValue }

    enum Group {
        case exterior
        case wheels
        case cabin
    }

    var group: Group {
        switch self {
        case .front, .frontRight, .right, .rearRight,
             .rear, .rearLeft, .left, .frontLeft:
            return .exterior
        case .wheelFrontLeft, .wheelFrontRight, .wheelRearLeft, .wheelRearRight:
            return .wheels
        case .dashboard:
            return .cabin
        }
    }

    /// Everything that appears as a marker on the car diagram.
    static var mapped: [PhotoAngle] {
        allCases.filter { $0.group == .exterior || $0.group == .wheels }
    }

    /// Position on the diagram, in normalised map coordinates. The car body
    /// occupies x 0.30…0.70 and y 0.13…0.87, so the exterior markers ring it
    /// and the wheel markers straddle its edge where the wheels actually are.
    var mapPosition: UnitPoint? {
        switch self {
        case .front:      return UnitPoint(x: 0.50, y: 0.045)
        case .frontRight: return UnitPoint(x: 0.815, y: 0.145)
        case .right:      return UnitPoint(x: 0.885, y: 0.50)
        case .rearRight:  return UnitPoint(x: 0.815, y: 0.855)
        case .rear:       return UnitPoint(x: 0.50, y: 0.955)
        case .rearLeft:   return UnitPoint(x: 0.185, y: 0.855)
        case .left:       return UnitPoint(x: 0.115, y: 0.50)
        case .frontLeft:  return UnitPoint(x: 0.185, y: 0.145)
        case .wheelFrontLeft:  return UnitPoint(x: 0.285, y: 0.285)
        case .wheelFrontRight: return UnitPoint(x: 0.715, y: 0.285)
        case .wheelRearLeft:   return UnitPoint(x: 0.285, y: 0.715)
        case .wheelRearRight:  return UnitPoint(x: 0.715, y: 0.715)
        case .dashboard:  return nil
        }
    }

    /// Position in the walk-around, 1-based — also the file-name prefix, so
    /// an alphabetical listing of the folder is in walk-around order.
    var order: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    /// `01-front` — stable, lowercase, safe in a Storage path.
    var fileTag: String {
        String(format: "%02d-%@", order, Self.slug(rawValue))
    }

    var labelKey: LocalizedStringKey {
        switch self {
        case .front:      return "angle_front"
        case .frontRight: return "angle_front_right"
        case .right:      return "angle_right"
        case .rearRight:  return "angle_rear_right"
        case .rear:       return "angle_rear"
        case .rearLeft:   return "angle_rear_left"
        case .left:       return "angle_left"
        case .frontLeft:  return "angle_front_left"
        case .wheelFrontLeft:  return "angle_wheel_front_left"
        case .wheelFrontRight: return "angle_wheel_front_right"
        case .wheelRearLeft:   return "angle_wheel_rear_left"
        case .wheelRearRight:  return "angle_wheel_rear_right"
        case .dashboard:  return "angle_dashboard"
        }
    }

    var icon: String {
        switch group {
        case .exterior: return "camera.fill"
        case .wheels:   return "circle.dashed"
        case .cabin:    return "speedometer"
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

    /// `wheelFrontLeft` → `wheel-front-left`.
    private static func slug(_ camel: String) -> String {
        var out = ""
        for character in camel {
            if character.isUppercase {
                out.append("-")
                out.append(Character(character.lowercased()))
            } else {
                out.append(character)
            }
        }
        return out
    }
}

/// A section that accepts any number of photos rather than one named shot.
enum PhotoCollection: String, CaseIterable, Identifiable, Equatable {
    /// Seats, trim, boot — whatever the cabin needs to show.
    case interior
    /// Anything beyond the guide: close-ups of damage, the fuel gauge.
    case additional

    var id: String { rawValue }

    /// Sorts after every named slot, so extras trail the walk-around.
    var fileTag: String {
        switch self {
        case .interior:   return "50-interior"
        case .additional: return "90-additional"
        }
    }

    var labelKey: LocalizedStringKey {
        switch self {
        case .interior:   return "collection_interior"
        case .additional: return "additional_photos"
        }
    }

    var hintKey: LocalizedStringKey {
        switch self {
        case .interior:   return "collection_interior_hint"
        case .additional: return "additional_photos_hint"
        }
    }

    var icon: String {
        switch self {
        case .interior:   return "carseat.left.fill"
        case .additional: return "plus.viewfinder"
        }
    }
}
