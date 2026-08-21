//
//  ContentView.swift
//  GM Assistant
//
//  Root router: RES entry screen until a reservation session exists,
//  then the reservation home.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let reservation = appState.reservation {
                ReservationHomeView(reservation: reservation)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                WelcomeView()
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: appState.reservation != nil)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
