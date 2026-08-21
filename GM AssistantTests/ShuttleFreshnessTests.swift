//
//  ShuttleFreshnessTests.swift
//  GM AssistantTests
//
//  The staleness thresholds decide whether the customer is shown a live ETA
//  or told the position is unreliable. Showing a confident "3 min away" from
//  a four-minute-old fix is the failure this guards against.
//

import Testing
import Foundation
@testable import GM_Assistant

struct ShuttleFreshnessTests {

    private let now = Date(timeIntervalSince1970: 1_784_721_600)

    private func driver(agedBy seconds: TimeInterval) -> ShuttleDriverLocation {
        ShuttleDriverLocation(
            id: "driver-1",
            driverName: "Shuttle",
            latitude: 47.45,
            longitude: 8.56,
            updatedAt: now.addingTimeInterval(-seconds),
            speedMps: nil
        )
    }

    @Test func freshDriverIsNeitherStaleNorExpired() {
        let d = driver(agedBy: 10)
        #expect(d.isStale(asOf: now) == false)
        #expect(d.isExpired(asOf: now) == false)
    }

    @Test func stalenessBeginsAfterNinetySeconds() {
        #expect(driver(agedBy: 90).isStale(asOf: now) == false, "exactly 90 s is still fresh")
        #expect(driver(agedBy: 91).isStale(asOf: now))
    }

    @Test func expiryBeginsAfterThreeMinutes() {
        #expect(driver(agedBy: 180).isExpired(asOf: now) == false)
        #expect(driver(agedBy: 181).isExpired(asOf: now))
        // Expired implies stale — the UI relies on that ordering.
        #expect(driver(agedBy: 181).isStale(asOf: now))
    }

    /// A driver document written by a phone with a skewed clock can carry a
    /// timestamp in the future; age must never go negative or the freshness
    /// maths inverts.
    @Test func futureTimestampClampsToZeroAge() {
        let d = driver(agedBy: -600)
        #expect(d.secondsSinceUpdate(asOf: now) == 0)
        #expect(d.isStale(asOf: now) == false)
    }

    @Test func ageTextFormatsBySize() {
        #expect(ShuttleDriverLocation.ageText(seconds: 0) == "0s")
        #expect(ShuttleDriverLocation.ageText(seconds: 45) == "45s")
        #expect(ShuttleDriverLocation.ageText(seconds: 59) == "59s")
        #expect(ShuttleDriverLocation.ageText(seconds: 60) == "1 min")
        #expect(ShuttleDriverLocation.ageText(seconds: 3599) == "59 min")
        #expect(ShuttleDriverLocation.ageText(seconds: 3600) == "1h 0m")
        #expect(ShuttleDriverLocation.ageText(seconds: 7830) == "2h 10m")
    }

    @Test func ageTextNeverShowsNegativeTime() {
        #expect(ShuttleDriverLocation.ageText(seconds: -30) == "0s")
    }
}
