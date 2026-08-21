//
//  GM_AssistantApp.swift
//  GM Assistant
//
//  Customer companion app for Green Motion rentals.
//  Customers enter their RES code to see their reservation, upload
//  check-out / return / damage photos, request a shuttle and call
//  roadside assistance or the GM office. Submissions appear live in
//  the staff app's vehicle detail screen ("Customer Records").
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct GM_AssistantApp: App {
    @State private var appState = AppState()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .tint(GMTheme.accent)
                // Light is the designed-for case; the palette carries a matching
                // dark variant, so the app follows the customer's own setting.
                .task {
                    // Prepared up front so the first haptic of the session
                    // lands with the touch instead of a beat after it.
                    Haptics.warmUp()
                    await appState.bootstrap()
                }
        }
    }
}
