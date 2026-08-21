//
//  GMConfig.swift
//  GM Assistant
//
//  Every value that is baked into the binary lives here, so changing one
//  is a one-line edit in one file rather than a hunt through views.
//
//  These are deliberately NOT read from Firestore. The customer session is
//  anonymous, and anonymous auth is explicitly excluded from reading the
//  franchise document (a deliberate fix on the backend after that document
//  turned out to expose every franchise's data). Moving these to remote
//  config therefore needs a backend change first: a small, world-readable
//  public config document, or extra fields on the reservation callable's
//  whitelisted response — the latter is the cheaper option, since the
//  callable already returns `roadsidePhone` and `officePhone` this way.
//

import Foundation

enum GMConfig {

    /// Roadside number used only *before* a reservation resolves — the
    /// franchise-specific number normally arrives with the reservation and
    /// takes precedence. This exists so a customer who is locked out of
    /// lookup entirely can still reach a human.
    static let fallbackRoadsidePhone = "+41765373407"

    /// Welcome offer shown on the entry screen.
    static let promoCode = "ZURICH23"

    static let promoURL = URL(
        string: "https://greenmotion.com/de/locations/switzerland/zurich-airport"
    )

    /// Most photos a single submission may carry. The backend rule caps the
    /// stored array at 60; this is the friendlier client-side limit.
    static let maxPhotosPerSubmission = 20

    /// How close to the planned return the app starts nudging about it.
    static let returnDueSoonWindow: TimeInterval = 24 * 60 * 60
}
