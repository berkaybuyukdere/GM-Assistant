//
//  GMLog.swift
//  GM Assistant
//
//  Replaces scattered `print()` calls with os.Logger, so failures are
//  visible in Console.app and in sysdiagnose from a real customer's phone —
//  not only in a debugger someone happens to have attached.
//
//  `GMLog.failure` is the single funnel for non-fatal errors. When crash
//  reporting is added, that one function is the only place that needs to
//  forward to it; nothing else in the app has to change.
//
//  Adding Crashlytics itself is a manual step in Xcode (add the
//  firebase-ios-sdk `FirebaseCrashlytics` product to the app target, plus
//  the dSYM upload build phase) — it cannot be done safely by editing the
//  project file from outside Xcode.
//

import Foundation
import OSLog

enum GMLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.GM-Assistant"

    static let session = Logger(subsystem: subsystem, category: "session")
    static let records = Logger(subsystem: subsystem, category: "records")
    static let upload = Logger(subsystem: subsystem, category: "upload")
    static let shuttle = Logger(subsystem: subsystem, category: "shuttle")

    /// Records a non-fatal failure. `context` is a short, stable string
    /// describing the operation ("resolve reservation", "photo upload") so
    /// entries group sensibly once they reach a dashboard.
    static func failure(
        _ logger: Logger,
        _ context: String,
        error: Error? = nil
    ) {
        if let error {
            logger.error("\(context, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        } else {
            logger.error("\(context, privacy: .public) failed")
        }
        // Crashlytics.crashlytics().record(error:) goes here once the SDK is added.
    }

    static func info(_ logger: Logger, _ message: String) {
        logger.info("\(message, privacy: .public)")
    }
}
