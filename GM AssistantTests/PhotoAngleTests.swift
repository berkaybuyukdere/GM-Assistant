//
//  PhotoAngleTests.swift
//  GM AssistantTests
//
//  The file tag is the only thing that carries "which shot is this" to the
//  backend, so its shape is a contract with whoever reads the Storage
//  folder — not a cosmetic detail. The map positions are a second contract,
//  this one with the customer: a marker in the wrong place sends them to
//  photograph the wrong corner.
//

import Testing
import SwiftUI
@testable import GM_Assistant

struct PhotoAngleTests {

    @Test func ordersRunFromOneWithoutGaps() {
        let orders = PhotoAngle.allCases.map(\.order)
        #expect(orders == Array(1...PhotoAngle.allCases.count))
    }

    /// Zero-padded so an alphabetical listing of the Storage folder comes out
    /// in walk-around order rather than 1, 10, 2.
    @Test func fileTagsSortIntoWalkAroundOrder() {
        let tags = PhotoAngle.allCases.map(\.fileTag)
        #expect(tags == tags.sorted())
        #expect(PhotoAngle.front.fileTag == "01-front")
        #expect(PhotoAngle.dashboard.fileTag == "13-dashboard")
    }

    /// Camel-cased cases have to come out as readable, path-safe slugs.
    @Test func multiWordCasesSlugify() {
        #expect(PhotoAngle.frontRight.fileTag == "02-front-right")
        #expect(PhotoAngle.wheelFrontLeft.fileTag == "09-wheel-front-left")
        #expect(PhotoAngle.wheelRearRight.fileTag == "12-wheel-rear-right")
    }

    @Test func fileTagsAreUniqueAndPathSafe() {
        let tags = PhotoAngle.allCases.map(\.fileTag)
        #expect(Set(tags).count == tags.count)
        for tag in tags {
            #expect(tag.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
        }
    }

    /// Collections upload alongside the named slots, so their tags must not
    /// collide with a slot tag and must sort after every one of them.
    @Test func collectionTagsSortAfterEverySlot() {
        let lastSlot = PhotoAngle.allCases.map(\.fileTag).max() ?? ""
        for collection in PhotoCollection.allCases {
            #expect(collection.fileTag > lastSlot)
        }
        #expect(PhotoCollection.interior.fileTag != PhotoCollection.additional.fileTag)
    }

    // MARK: - Coverage

    @Test func everyCornerAndEveryWheelIsCovered() {
        let exterior = PhotoAngle.allCases.filter { $0.group == .exterior }
        #expect(exterior.count == 8, "four flat sides plus four corners")

        let wheels = PhotoAngle.allCases.filter { $0.group == .wheels }
        #expect(wheels.count == 4, "a car has four wheels, so four slots")
    }

    // MARK: - Map

    @Test func everyMappedAngleHasAPositionAndTheRestDoNot() {
        for angle in PhotoAngle.mapped {
            #expect(angle.mapPosition != nil)
        }
        #expect(PhotoAngle.dashboard.mapPosition == nil)
        #expect(PhotoAngle.mapped.count == 12)
    }

    @Test func mapPositionsStayInsideTheCanvas() {
        for angle in PhotoAngle.mapped {
            let point = angle.mapPosition!
            #expect(point.x >= 0 && point.x <= 1)
            #expect(point.y >= 0 && point.y <= 1)
        }
    }

    /// Two markers on the same spot would be untappable, and a marker on the
    /// wrong side of the car would be actively misleading.
    @Test func markersAreDistinctAndOnTheCorrectSide() {
        let points = PhotoAngle.mapped.map { $0.mapPosition! }
        for (i, a) in points.enumerated() {
            for b in points[(i + 1)...] {
                let distance = hypot(a.x - b.x, a.y - b.y)
                #expect(distance > 0.10, "markers must not overlap")
            }
        }

        // Left-hand shots sit left of centre, right-hand shots right of it.
        for angle in [PhotoAngle.left, .frontLeft, .rearLeft, .wheelFrontLeft, .wheelRearLeft] {
            #expect(angle.mapPosition!.x < 0.5)
        }
        for angle in [PhotoAngle.right, .frontRight, .rearRight, .wheelFrontRight, .wheelRearRight] {
            #expect(angle.mapPosition!.x > 0.5)
        }
        // Front shots sit above centre, rear shots below.
        for angle in [PhotoAngle.front, .frontLeft, .frontRight, .wheelFrontLeft, .wheelFrontRight] {
            #expect(angle.mapPosition!.y < 0.5)
        }
        for angle in [PhotoAngle.rear, .rearLeft, .rearRight, .wheelRearLeft, .wheelRearRight] {
            #expect(angle.mapPosition!.y > 0.5)
        }
    }

    // MARK: - Guide

    /// Check-out and return get compared against each other, so they must ask
    /// for exactly the same shots.
    @Test func checkoutAndReturnShareOneShotList() {
        #expect(PhotoAngle.guide(for: .checkoutPhotos) == PhotoAngle.allCases)
        #expect(PhotoAngle.guide(for: .returnPhotos) == PhotoAngle.allCases)
    }

    @Test func otherRecordTypesStayFreeForm() {
        #expect(PhotoAngle.guide(for: .damagePhotos).isEmpty)
        #expect(PhotoAngle.guide(for: .note).isEmpty)
        #expect(PhotoAngle.guide(for: .shuttleRequest).isEmpty)
    }

    /// A full guided set has to leave room for cabin and extra photos inside
    /// the client cap, which itself sits under the backend's 60-photo limit.
    @Test func aFullGuideLeavesRoomForExtras() {
        #expect(PhotoAngle.allCases.count < GMConfig.maxPhotosPerSubmission)
        #expect(GMConfig.maxPhotosPerSubmission - PhotoAngle.allCases.count >= 5)
    }
}
