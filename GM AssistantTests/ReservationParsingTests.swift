//
//  ReservationParsingTests.swift
//  GM AssistantTests
//
//  The reservation arrives as an untyped dictionary from a Cloud Function.
//  This is the app's only trust boundary with the backend, and the place a
//  contract change would land first.
//

import Testing
import Foundation
import CoreLocation
@testable import GM_Assistant

struct ReservationParsingTests {

    private func payload(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var base: [String: Any] = [
            "resKodu": "RES-48213",
            "franchiseId": "CH",
            "aracId": "vehicle-1",
            "aracPlaka": "ZH 481 233",
            "customerName": "Berkay Büyükdere",
            "checkoutAt": "2026-07-22T14:30:00Z",
            "plannedReturnAt": "2026-07-25T10:00:00Z",
            "pickUpBranch": "Zürich Airport",
            "dropOffBranch": "Zürich Airport",
            "vehicleMake": "BMW",
            "vehicleModel": "M5 CS",
            "roadsidePhone": "+41 44 555 00 00",
            "officePhone": "+41 44 555 12 34",
        ]
        for (key, value) in overrides { base[key] = value }
        return base
    }

    @Test func parsesAWellFormedPayload() throws {
        let reservation = try #require(CustomerReservation(callableData: payload()))
        #expect(reservation.resKodu == "RES-48213")
        #expect(reservation.franchiseId == "CH")
        #expect(reservation.aracPlaka == "ZH 481 233")
        #expect(reservation.vehicleDisplayName == "BMW M5 CS")
        #expect(reservation.checkoutAt != nil)
        #expect(reservation.plannedReturnAt != nil)
    }

    /// Without these two the session cannot be scoped to a franchise, so the
    /// initialiser must refuse rather than produce a half-built reservation.
    @Test func rejectsMissingIdentifiers() {
        var noRes = payload(); noRes.removeValue(forKey: "resKodu")
        #expect(CustomerReservation(callableData: noRes) == nil)

        var noFranchise = payload(); noFranchise.removeValue(forKey: "franchiseId")
        #expect(CustomerReservation(callableData: noFranchise) == nil)

        #expect(CustomerReservation(callableData: payload(["resKodu": ""])) == nil)
        #expect(CustomerReservation(callableData: payload(["franchiseId": ""])) == nil)
    }

    /// The backend has emitted both plain and fractional-second ISO 8601.
    @Test func parsesBothISO8601Shapes() throws {
        let plain = try #require(CustomerReservation(callableData: payload()))
        #expect(plain.checkoutAt != nil)

        let fractional = try #require(CustomerReservation(
            callableData: payload(["checkoutAt": "2026-07-22T14:30:00.123Z"])
        ))
        #expect(fractional.checkoutAt != nil)
    }

    @Test func unparsableDatesBecomeNilRatherThanFailingTheWholeLookup() throws {
        let reservation = try #require(CustomerReservation(
            callableData: payload(["checkoutAt": "not a date"])
        ))
        #expect(reservation.checkoutAt == nil)
        #expect(reservation.resKodu == "RES-48213")
    }

    @Test func missingRoadsideNumberFallsBackToTheBundledOne() throws {
        var data = payload(); data.removeValue(forKey: "roadsidePhone")
        let reservation = try #require(CustomerReservation(callableData: data))
        #expect(reservation.roadsidePhone == GMConfig.fallbackRoadsidePhone)
    }

    @Test func blankStringsAreTreatedAsAbsent() throws {
        let reservation = try #require(CustomerReservation(
            callableData: payload(["customerName": "   ", "officePhone": ""])
        ))
        #expect(reservation.customerName == nil)
        #expect(reservation.officePhone == nil)
    }

    @Test func vehicleNameToleratesAPartialVehicle() throws {
        var onlyMake = payload(); onlyMake.removeValue(forKey: "vehicleModel")
        #expect(try #require(CustomerReservation(callableData: onlyMake)).vehicleDisplayName == "BMW")

        var neither = payload()
        neither.removeValue(forKey: "vehicleMake")
        neither.removeValue(forKey: "vehicleModel")
        #expect(try #require(CustomerReservation(callableData: neither)).vehicleDisplayName.isEmpty)
    }

    @Test func acceptsAValidShuttleMeetingPoint() throws {
        let reservation = try #require(CustomerReservation(callableData: payload([
            "shuttleMeetingPoint": ["lat": 47.4515, "lng": 8.5646, "label": "Terminal 2"]
        ])))
        #expect(reservation.shuttleMeetingLabel == "Terminal 2")
        let coordinate = try #require(reservation.shuttleMeetingCoordinate)
        #expect(abs(coordinate.latitude - 47.4515) < 0.0001)
        #expect(abs(coordinate.longitude - 8.5646) < 0.0001)
    }

    /// An out-of-range coordinate would drop a map pin somewhere impossible;
    /// it must be discarded, not clamped.
    @Test func rejectsImpossibleCoordinates() throws {
        let reservation = try #require(CustomerReservation(callableData: payload([
            "shuttleMeetingPoint": ["lat": 191.0, "lng": 8.5646]
        ])))
        #expect(reservation.shuttleMeetingCoordinate == nil)
    }

    @Test func meetingPointWithoutALabelStillYieldsACoordinate() throws {
        let reservation = try #require(CustomerReservation(callableData: payload([
            "shuttleMeetingPoint": ["lat": 47.4515, "lng": 8.5646]
        ])))
        #expect(reservation.shuttleMeetingCoordinate != nil)
        #expect(reservation.shuttleMeetingLabel == nil)
    }

    /// The reservation is cached to disk between launches, so it has to make
    /// the round trip through Codable without losing anything.
    @Test func survivesPersistenceRoundTrip() throws {
        let original = try #require(CustomerReservation(callableData: payload([
            "shuttleMeetingPoint": ["lat": 47.4515, "lng": 8.5646, "label": "Terminal 2"]
        ])))
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(CustomerReservation.self, from: data)
        #expect(restored == original)
    }
}
