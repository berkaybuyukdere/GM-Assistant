//
//  Haptics.swift
//  GM Assistant
//
//  Tiny haptic helper for the key confirmation moments (submit, shuttle
//  toggle, upload success) — cheap polish that makes the app feel native.
//

import UIKit

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
