//
//  RentalStatus.swift
//  GM Assistant
//
//  Where the customer is in their rental, derived from the two dates the
//  reservation already carries. The home screen was previously identical
//  whether someone was collecting the car tomorrow or returning it in an
//  hour; this is what lets it lead with the thing that matters now.
//
//  Deliberately free of SwiftUI so the boundaries can be unit-tested against
//  a fixed clock rather than "whatever time the test happened to run".
//

import Foundation

struct RentalStatus: Equatable {

    enum Phase: String, Equatable {
        /// Reservation exists, the car has not been collected yet.
        case beforePickup
        /// Collected, with the return comfortably ahead.
        case active
        /// Return is inside the nudge window.
        case dueSoon
        /// Planned return time has passed.
        case overdue
        /// Not enough date information to say.
        case unknown
    }

    let phase: Phase
    /// The moment any countdown refers to — pickup for `beforePickup`,
    /// planned return for the rest. `nil` when unknown.
    let reference: Date?

    static func make(
        checkoutAt: Date?,
        plannedReturnAt: Date?,
        now: Date = Date(),
        dueSoonWindow: TimeInterval = GMConfig.returnDueSoonWindow
    ) -> RentalStatus {
        if let checkoutAt, now < checkoutAt {
            return RentalStatus(phase: .beforePickup, reference: checkoutAt)
        }

        if let plannedReturnAt {
            if now > plannedReturnAt {
                return RentalStatus(phase: .overdue, reference: plannedReturnAt)
            }
            if plannedReturnAt.timeIntervalSince(now) <= dueSoonWindow {
                return RentalStatus(phase: .dueSoon, reference: plannedReturnAt)
            }
            return RentalStatus(phase: .active, reference: plannedReturnAt)
        }

        // Pickup is behind us but there is no return date to count towards.
        if checkoutAt != nil {
            return RentalStatus(phase: .active, reference: nil)
        }

        return RentalStatus(phase: .unknown, reference: nil)
    }

    static func make(
        reservation: CustomerReservation,
        now: Date = Date()
    ) -> RentalStatus {
        make(
            checkoutAt: reservation.checkoutAt,
            plannedReturnAt: reservation.plannedReturnAt,
            now: now
        )
    }

    /// True while the return is the customer's next obligation — used to
    /// decide which photo action the home screen should lead with.
    var isReturnFocused: Bool {
        phase == .dueSoon || phase == .overdue
    }
}
