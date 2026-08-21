//
//  RentalStatusTests.swift
//  GM AssistantTests
//
//  The phase boundaries decide what the home screen leads with, so they are
//  pinned against a fixed clock rather than "whenever the test ran".
//

import Testing
import Foundation
@testable import GM_Assistant

struct RentalStatusTests {

    /// 2026-07-22 12:00:00 UTC — every case below is expressed relative to this.
    private let now = Date(timeIntervalSince1970: 1_784_721_600)

    private func offset(_ hours: Double) -> Date {
        now.addingTimeInterval(hours * 3600)
    }

    @Test func pickupStillAheadIsBeforePickup() {
        let status = RentalStatus.make(
            checkoutAt: offset(6),
            plannedReturnAt: offset(72),
            now: now
        )
        #expect(status.phase == .beforePickup)
        #expect(status.reference == offset(6))
        #expect(status.isReturnFocused == false)
    }

    @Test func collectedWithReturnFarAwayIsActive() {
        let status = RentalStatus.make(
            checkoutAt: offset(-24),
            plannedReturnAt: offset(72),
            now: now
        )
        #expect(status.phase == .active)
        // An active rental counts towards the return, not the pickup.
        #expect(status.reference == offset(72))
    }

    @Test func returnInsideTheWindowIsDueSoon() {
        let status = RentalStatus.make(
            checkoutAt: offset(-48),
            plannedReturnAt: offset(6),
            now: now
        )
        #expect(status.phase == .dueSoon)
        #expect(status.isReturnFocused)
    }

    @Test func pastPlannedReturnIsOverdue() {
        let status = RentalStatus.make(
            checkoutAt: offset(-72),
            plannedReturnAt: offset(-1),
            now: now
        )
        #expect(status.phase == .overdue)
        #expect(status.isReturnFocused)
    }

    /// The two edges of the 24 h nudge window, which is where an off-by-one
    /// would quietly show the wrong screen for a whole day.
    @Test func dueSoonWindowBoundaries() {
        let exactlyAtWindow = RentalStatus.make(
            checkoutAt: offset(-48),
            plannedReturnAt: now.addingTimeInterval(GMConfig.returnDueSoonWindow),
            now: now
        )
        #expect(exactlyAtWindow.phase == .dueSoon, "the window edge counts as due soon")

        let justOutside = RentalStatus.make(
            checkoutAt: offset(-48),
            plannedReturnAt: now.addingTimeInterval(GMConfig.returnDueSoonWindow + 1),
            now: now
        )
        #expect(justOutside.phase == .active)
    }

    /// The instant of pickup belongs to the rental, not to the wait for it.
    @Test func pickupInstantIsNoLongerBeforePickup() {
        let status = RentalStatus.make(
            checkoutAt: now,
            plannedReturnAt: offset(72),
            now: now
        )
        #expect(status.phase == .active)
    }

    @Test func missingDatesAreUnknown() {
        let status = RentalStatus.make(checkoutAt: nil, plannedReturnAt: nil, now: now)
        #expect(status.phase == .unknown)
        #expect(status.reference == nil)
    }

    /// Collected, but the reservation carried no return date — still active,
    /// just with nothing to count towards.
    @Test func pickupWithoutReturnDateIsActiveWithoutReference() {
        let status = RentalStatus.make(
            checkoutAt: offset(-5),
            plannedReturnAt: nil,
            now: now
        )
        #expect(status.phase == .active)
        #expect(status.reference == nil)
    }
}
