//
//  GMTheme.swift
//  GM Assistant
//
//  Customer-facing design system: large touch targets, adaptive
//  light/dark colors, one brand accent (Green Motion green).
//

import SwiftUI

enum GMTheme {
    /// Green Motion brand green (adaptive: brighter in dark mode for contrast).
    static let accent = Color(
        light: Color(red: 0.0, green: 0.45, blue: 0.20),
        dark: Color(red: 0.35, green: 0.78, blue: 0.36)
    )

    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let danger = Color(.systemRed)
    static let warning = Color(.systemOrange)

    static let cardCornerRadius: CGFloat = 16

    /// Deep-to-bright brand gradient — used for the promo banner and other
    /// high-emphasis surfaces that should read as "special" against the
    /// otherwise flat, neutral card system.
    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.02, green: 0.32, blue: 0.16),
            Color(red: 0.10, green: 0.55, blue: 0.27),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardShadowColor = Color.black.opacity(0.08)

    static func titleFont(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func bodyFont(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .regular)
    }

    static func labelFont(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .semibold)
    }
}

extension Color {
    /// Adaptive color from a light and dark variant.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

/// Shared card container used across screens.
struct GMCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(GMTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: GMTheme.cardCornerRadius, style: .continuous))
        .shadow(color: GMTheme.cardShadowColor, radius: 10, x: 0, y: 4)
    }
}

/// Small circular icon badge (colored background + symbol) used to give
/// list rows and section headers a consistent, more polished look than a
/// bare `Image(systemName:)`.
struct GMIconBadge: View {
    let systemName: String
    var tint: Color = GMTheme.accent
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.15))
            Image(systemName: systemName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

/// Big rounded primary action button style.
struct GMPrimaryButtonStyle: ButtonStyle {
    var color: Color = GMTheme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
