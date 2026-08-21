//
//  Haptics.swift
//  GM Assistant
//
//  Haptic vocabulary for the app. Each case means one thing, so the phone
//  is saying something consistent rather than buzzing on every touch:
//
//    tap        — a plain button or navigation
//    select     — an item became the chosen one (a shot slot, yes/no)
//    toggle     — something opened or closed
//    capture    — a photo landed in a slot
//    success    — a submission reached the backend
//    warning    — the action went through, but something needs attention
//    error      — it did not go through
//
//  Generators are prepared before use: without that first call the Taptic
//  Engine spins up lazily and the very first feedback of a session arrives
//  late enough to feel disconnected from the touch.
//

import UIKit

enum Haptics {

    // MARK: - Vocabulary

    /// Plain button press, navigation, opening a sheet.
    static func tap() {
        impact(.light)
    }

    /// A choice was made: a shot slot picked, a yes/no answered.
    static func select() {
        selection.selectionChanged()
        selection.prepare()
    }

    /// A section expanded or collapsed.
    static func toggle() {
        impact(.soft)
    }

    /// A photo was taken or added — heavier than a tap, this is a result.
    static func capture() {
        impact(.medium)
    }

    /// Something was removed.
    static func remove() {
        impact(.rigid)
    }

    static func success() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    static func warning() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    static func error() {
        notification.notificationOccurred(.error)
        notification.prepare()
    }

    /// Call once at launch so the first haptic of the session is on time.
    static func warmUp() {
        selection.prepare()
        notification.prepare()
        for generator in impacts.values { generator.prepare() }
    }

    // MARK: - Legacy name

    /// Older call sites used `light()`; it is the same as `tap()`.
    static func light() { tap() }

    // MARK: - Generators

    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    private static let impacts: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [
        .light: UIImpactFeedbackGenerator(style: .light),
        .soft: UIImpactFeedbackGenerator(style: .soft),
        .medium: UIImpactFeedbackGenerator(style: .medium),
        .rigid: UIImpactFeedbackGenerator(style: .rigid),
    ]

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard let generator = impacts[style] else { return }
        generator.impactOccurred()
        generator.prepare()
    }
}
