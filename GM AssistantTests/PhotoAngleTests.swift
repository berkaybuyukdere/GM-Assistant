//
//  PhotoAngleTests.swift
//  GM AssistantTests
//
//  The file tag is the only thing that carries "which shot is this" to the
//  backend, so its shape is a contract with whoever reads the Storage
//  folder — not a cosmetic detail.
//

import Testing
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
        #expect(PhotoAngle.dashboard.fileTag == "07-dashboard")
    }

    @Test func fileTagsAreUniqueAndPathSafe() {
        let tags = PhotoAngle.allCases.map(\.fileTag)
        #expect(Set(tags).count == tags.count)
        for tag in tags {
            #expect(tag.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
        }
    }

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

    /// A full guided set plus extras has to stay inside the client cap, which
    /// itself sits under the backend's 60-photo array limit.
    @Test func aFullGuideFitsWithinTheSubmissionCap() {
        #expect(PhotoAngle.allCases.count < GMConfig.maxPhotosPerSubmission)
    }
}
