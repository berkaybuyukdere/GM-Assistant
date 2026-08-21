//
//  GMTheme.swift
//  GM Assistant
//
//  A Palantir-adjacent design system, softened for customers.
//
//  What it keeps from that language: structure you can read at a glance —
//  titled panels, hairline separation, aligned data columns, a single
//  accent that means "action" and "live", and restraint everywhere else.
//
//  What it deliberately drops: the operations-console tone. No console
//  jargon, no razor-sharp corners, no engineering grid, no wall of
//  uppercase. Corners are gently rounded, panels sit on a warm off-white,
//  and only the things that really are codes — reservation numbers,
//  plates — are set in monospace.
//
//  Light is the designed-for case; the dark variant is derived from it so
//  the app still looks intentional at night.
//

import SwiftUI

enum GMTheme {

    // MARK: - Surfaces

    /// App canvas — a warm off-white with the faintest green in it.
    static let background = Color(
        light: Color(hex: 0xF4F7F5),
        dark: Color(hex: 0x0E1116)
    )
    /// Standard panel surface.
    static let surface = Color(
        light: .white,
        dark: Color(hex: 0x171B21)
    )
    /// Recessed surface: inputs, wells, thumbnails inside a panel.
    static let surfaceInset = Color(
        light: Color(hex: 0xF5F7F9),
        dark: Color(hex: 0x0B0E12)
    )
    /// Raised surface: selected rows, pressed controls.
    static let surfaceRaised = Color(
        light: Color(hex: 0xEDF1F4),
        dark: Color(hex: 0x232830)
    )

    // MARK: - Lines

    static let border = Color(
        light: Color(hex: 0xE3E8EC),
        dark: Color(hex: 0x2A3038)
    )
    static let borderStrong = Color(
        light: Color(hex: 0xCBD4DB),
        dark: Color(hex: 0x3A424D)
    )
    static let divider = Color(
        light: Color.black.opacity(0.055),
        dark: Color.white.opacity(0.055)
    )

    // MARK: - Accent
    //
    // Named by role, not by lightness, so both themes stay legible:
    // `accent` fills, `accentText` is read, `onAccent` sits on top of a fill.

    /// Primary fill: buttons, active bars, live markers.
    static let accent = Color(
        light: Color(hex: 0x12915F),
        dark: Color(hex: 0x2FAE6B)
    )
    /// Green used for text and glyphs directly on the canvas.
    static let accentText = Color(
        light: Color(hex: 0x0B6E47),
        dark: Color(hex: 0x6EDBA3)
    )
    /// Translucent wash behind selected/active content.
    static let accentSoft = Color(
        light: Color(hex: 0x12915F).opacity(0.09),
        dark: Color(hex: 0x2FAE6B).opacity(0.14)
    )
    /// Foreground on top of an `accent` fill.
    static let onAccent = Color(
        light: .white,
        dark: Color(hex: 0x08120C)
    )

    // MARK: - Text

    static let textPrimary = Color(
        light: Color(hex: 0x161D26),
        dark: Color(hex: 0xEDF0F3)
    )
    static let textSecondary = Color(
        light: Color(hex: 0x4E5966),
        dark: Color(hex: 0xA7B0BC)
    )
    static let textMuted = Color(
        light: Color(hex: 0x76818E),
        dark: Color(hex: 0x717D8B)
    )
    static let textFaint = Color(
        light: Color(hex: 0x9AA4AF),
        dark: Color(hex: 0x566068)
    )

    // MARK: - Status

    static let danger = Color(
        light: Color(hex: 0xC7443F),
        dark: Color(hex: 0xE0575B)
    )
    static let warning = Color(
        light: Color(hex: 0xB4741A),
        dark: Color(hex: 0xE8A33D)
    )
    static let info = Color(
        light: Color(hex: 0x2E6FCB),
        dark: Color(hex: 0x7FB2F0)
    )

    // MARK: - Metrics

    /// Softly rounded — crisp, but nothing here is a razor.
    static let radius: CGFloat = 10
    static let radiusTight: CGFloat = 7
    static let hairline: CGFloat = 1
    static let panelPadding: CGFloat = 15
    static let gutter: CGFloat = 12

    /// Barely-there lift, light theme only. In dark, panels separate by
    /// their border alone.
    static let panelShadow = Color(
        light: Color.black.opacity(0.045),
        dark: Color.clear
    )

    // MARK: - Type

    /// UI sans — labels, prose, button text, and most values.
    static func ui(_ size: CGFloat = 14, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Monospace — reserved for things that genuinely are codes:
    /// reservation numbers and plates. Not for dates or names.
    static func mono(_ size: CGFloat = 14, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Legacy aliases (kept so older call sites keep compiling)

    static let card = surface
    static let cardCornerRadius: CGFloat = radius
    static let accentBright = accentText

    static func titleFont(_ size: CGFloat = 28) -> Font { ui(size, .bold) }
    static func bodyFont(_ size: CGFloat = 16) -> Font { ui(size) }
    static func labelFont(_ size: CGFloat = 13) -> Font { ui(size, .semibold) }
}

extension Color {
    /// `Color(hex: 0x12915F)` — the palette is written the way a design spec
    /// is written, not as float triples.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Adaptive color from a light and dark variant.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

// MARK: - Section label

extension View {
    /// The small tracked label that titles a panel. Used for section headers
    /// only — field labels and body copy stay in sentence case, which is what
    /// keeps the interface from reading as a readout.
    func gmSectionLabel(_ size: CGFloat = 11, color: Color = GMTheme.textSecondary) -> some View {
        self.font(.system(size: size, weight: .semibold))
            .tracking(size * 0.07)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// Quiet caption used under fields and beside status dots.
    func gmCaption(_ size: CGFloat = 12, color: Color = GMTheme.textMuted) -> some View {
        self.font(.system(size: size, weight: .regular))
            .foregroundStyle(color)
    }

    /// 1px hairline frame in the panel geometry.
    func gmBorder(_ color: Color = GMTheme.border, radius: CGFloat = GMTheme.radius) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: GMTheme.hairline)
        )
    }

    /// Legacy name — older call sites used this for every small label.
    func gmMicroLabel(_ size: CGFloat = 10, color: Color = GMTheme.textMuted) -> some View {
        self.gmSectionLabel(size, color: color)
    }
}

// MARK: - Canvas

/// The standard screen background: a warm canvas lit by a soft green wash
/// from the top-left, so the brand colour is present as light in the room
/// rather than as decoration.
struct GMCanvas: View {
    var body: some View {
        ZStack {
            GMTheme.background
            RadialGradient(
                colors: [GMTheme.accent.opacity(0.07), .clear],
                center: UnitPoint(x: 0.1, y: -0.08),
                startRadius: 0,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Panel

/// The single container primitive: a surface, a hairline frame, and an
/// optional header — a short green tick followed by a section label.
struct GMPanel<Content: View, Accessory: View>: View {
    private let title: LocalizedStringKey?
    private let content: Content
    private let accessory: Accessory
    private var padding: CGFloat
    private var spacing: CGFloat

    init(
        _ title: LocalizedStringKey? = nil,
        padding: CGFloat = GMTheme.panelPadding,
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.padding = padding
        self.spacing = spacing
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(spacing: 9) {
                    Capsule()
                        .fill(GMTheme.accent)
                        .frame(width: 3, height: 12)
                    Text(title).gmSectionLabel()
                    Spacer(minLength: 8)
                    accessory
                }
                .padding(.horizontal, padding)
                .padding(.top, 13)
                .padding(.bottom, 11)

                Rectangle()
                    .fill(GMTheme.divider)
                    .frame(height: GMTheme.hairline)
            }

            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
        }
        .background(GMTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
        .gmBorder()
        .shadow(color: GMTheme.panelShadow, radius: 8, x: 0, y: 2)
    }
}

// MARK: - Data row

/// One label/value line. Sentence-case label on the left, value on the right
/// with monospaced digits so a stack of rows still lines up cleanly.
struct GMDataRow: View {
    let label: LocalizedStringKey
    let value: String
    var valueColor: Color = GMTheme.textPrimary
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(GMTheme.ui(13))
                .foregroundStyle(GMTheme.textMuted)
            Spacer(minLength: 8)
            Text(value)
                .font(mono ? GMTheme.mono(13, .semibold) : GMTheme.ui(13.5, .medium))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Chip

/// A soft-filled monospace chip: plate numbers, reservation codes.
struct GMChip: View {
    let text: String
    var tint: Color = GMTheme.accentText
    var size: CGFloat = 13

    var body: some View {
        Text(text)
            .font(GMTheme.mono(size, .semibold))
            .tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
    }
}

// MARK: - Status dot

/// Small round status indicator, optionally breathing to signal "live".
struct GMStatusDot: View {
    var color: Color = GMTheme.accent
    var size: CGFloat = 7
    var pulsing: Bool = false

    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(pulsing && on ? 0.3 : 1)
            .animation(
                pulsing ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default,
                value: on
            )
            .onAppear { if pulsing { on = true } }
    }
}

// MARK: - Icon frame

/// Softly rounded, tinted glyph holder.
struct GMIconFrame: View {
    let systemName: String
    var tint: Color = GMTheme.accent
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                .fill(tint.opacity(0.11))
            Image(systemName: systemName)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

/// Kept for older call sites.
struct GMIconBadge: View {
    let systemName: String
    var tint: Color = GMTheme.accent
    var size: CGFloat = 34

    var body: some View {
        GMIconFrame(systemName: systemName, tint: tint, size: size)
    }
}

// MARK: - Buttons

/// Filled green action.
///
/// Disabled does *not* mean "the same button, faded" — a translucent fill
/// with light text is unreadable. Disabled renders as an inert recessed slab
/// so the control still reads as a control, just an unavailable one.
struct GMPrimaryButtonStyle: ButtonStyle {
    var color: Color = GMTheme.accent
    var height: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        Slab(configuration: configuration, color: color, height: height)
    }

    private struct Slab: View {
        let configuration: GMPrimaryButtonStyle.Configuration
        let color: Color
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isEnabled ? GMTheme.onAccent : GMTheme.textFaint)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    isEnabled
                        ? (configuration.isPressed ? color.opacity(0.82) : color)
                        : GMTheme.surfaceInset
                )
                .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                        .strokeBorder(
                            isEnabled ? .clear : GMTheme.border,
                            lineWidth: GMTheme.hairline
                        )
                )
                .animation(.easeOut(duration: 0.14), value: isEnabled)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/// Outlined action — the secondary tier, for utility and emergency calls
/// that must not compete with the green primary.
struct GMGhostButtonStyle: ButtonStyle {
    var color: Color = GMTheme.textSecondary
    var height: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(configuration.isPressed ? color.opacity(0.10) : GMTheme.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                    .strokeBorder(color.opacity(0.28), lineWidth: GMTheme.hairline)
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Legacy card

/// Older screens still build `GMCard { ... }`; renders a headerless panel.
struct GMCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GMPanel {
            content
        }
    }
}

// MARK: - Collapsible panel

/// A panel whose header is a switch. Used for content that is reassuring to
/// have but noisy to always show — the submissions log grows with every
/// photo set, and once it is long it pushes the actions the customer came
/// for off the screen.
struct GMCollapsiblePanel<Content: View, Accessory: View>: View {
    private let title: LocalizedStringKey
    @Binding private var isExpanded: Bool
    private let content: Content
    private let accessory: Accessory
    private var padding: CGFloat
    private var spacing: CGFloat

    init(
        _ title: LocalizedStringKey,
        isExpanded: Binding<Bool>,
        padding: CGFloat = GMTheme.panelPadding,
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.padding = padding
        self.spacing = spacing
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.toggle()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    Capsule()
                        .fill(GMTheme.accent)
                        .frame(width: 3, height: 12)
                    Text(title).gmSectionLabel()
                    Spacer(minLength: 8)
                    accessory
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GMTheme.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, padding)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isExpanded ? [] : .isButton)

            if isExpanded {
                Rectangle()
                    .fill(GMTheme.divider)
                    .frame(height: GMTheme.hairline)

                VStack(alignment: .leading, spacing: spacing) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(padding)
            }
        }
        .background(GMTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
        .gmBorder()
        .shadow(color: GMTheme.panelShadow, radius: 8, x: 0, y: 2)
    }
}
