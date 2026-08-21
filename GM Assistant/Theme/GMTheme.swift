//
//  GMTheme.swift
//  GM Assistant
//
//  Palantir-inspired technical design system (Blueprint.js dark ramp) with
//  the Green Motion green promoted from a single brand tint to the primary
//  signal colour of the whole interface.
//
//  Rules the whole app follows:
//  • Near-black canvas. Panels are flat and separated by 1px hairlines —
//    never by shadows or blur.
//  • 2px corner radius. Instrument-panel geometry, not app-store roundness.
//  • Micro labels are UPPERCASE with wide tracking; every data value is
//    monospaced so codes, plates and timestamps align in a column.
//  • Green carries action and live state. Grey carries structure. Nothing
//    else gets colour unless it is a warning or a fault.
//

import SwiftUI

enum GMTheme {

    // MARK: - Surfaces

    /// App canvas — the deepest layer.
    static let background = Color(hex: 0x0E1116)
    /// Standard panel surface.
    static let surface = Color(hex: 0x171B21)
    /// Recessed surface: inputs, wells, thumbnails inside a panel.
    static let surfaceInset = Color(hex: 0x0B0E12)
    /// Raised surface: selected rows, pressed controls.
    static let surfaceRaised = Color(hex: 0x232830)

    // MARK: - Lines

    static let border = Color(hex: 0x2A3038)
    static let borderStrong = Color(hex: 0x3A424D)
    static let divider = Color.white.opacity(0.055)

    // MARK: - Green ramp — the primary accent

    static let green1 = Color(hex: 0x0C3A22)
    static let green2 = Color(hex: 0x14613A)
    static let green3 = Color(hex: 0x1E8A55)
    static let green4 = Color(hex: 0x2FAE6B)
    static let green5 = Color(hex: 0x6EDBA3)

    /// Primary action / live state.
    static let accent = green4
    /// Bright green for text and glyphs on dark surfaces.
    static let accentBright = green5
    /// Deep green for fills behind bright green content.
    static let accentDim = green2
    /// Translucent green wash for selected/active backgrounds.
    static let accentWash = green4.opacity(0.14)

    // MARK: - Text

    static let textPrimary = Color(hex: 0xEDF0F3)
    static let textSecondary = Color(hex: 0xA7B0BC)
    static let textMuted = Color(hex: 0x717D8B)
    static let textFaint = Color(hex: 0x566068)

    // MARK: - Status

    static let danger = Color(hex: 0xE0575B)
    static let warning = Color(hex: 0xE8A33D)
    static let info = Color(hex: 0x7FB2F0)

    // MARK: - Metrics

    /// Blueprint-sharp. Everything in the app uses this or `radiusTight`.
    static let radius: CGFloat = 3
    static let radiusTight: CGFloat = 2
    static let hairline: CGFloat = 1
    static let panelPadding: CGFloat = 14
    static let gutter: CGFloat = 12

    // MARK: - Type

    /// UI sans — labels, prose, button text.
    static func ui(_ size: CGFloat = 14, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Monospace — every value that is data: codes, plates, times, counts.
    static func mono(_ size: CGFloat = 14, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Legacy aliases (kept so older call sites keep compiling)

    static let card = surface
    static let cardCornerRadius: CGFloat = radius

    static func titleFont(_ size: CGFloat = 28) -> Font { ui(size, .bold) }
    static func bodyFont(_ size: CGFloat = 16) -> Font { ui(size) }
    static func labelFont(_ size: CGFloat = 13) -> Font { ui(size, .semibold) }
}

extension Color {
    /// `Color(hex: 0x2FAE6B)` — the palette above is written the way a design
    /// spec is written, not as float triples.
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

// MARK: - Micro label

extension View {
    /// The uppercase, wide-tracked micro label that titles every section and
    /// every data field in the interface.
    func gmMicroLabel(_ size: CGFloat = 10, color: Color = GMTheme.textMuted) -> some View {
        self.font(.system(size: size, weight: .semibold))
            .tracking(size * 0.14)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// 1px hairline frame in the panel geometry.
    func gmBorder(_ color: Color = GMTheme.border, radius: CGFloat = GMTheme.radius) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: GMTheme.hairline)
        )
    }
}

// MARK: - Technical grid backdrop

/// Faint engineering grid behind the canvas. Barely visible by design — it
/// reads as texture, not as a pattern.
struct GMGridBackground: View {
    var spacing: CGFloat = 28

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(.white.opacity(0.021)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// The standard screen background: canvas + grid + a soft green horizon glow
/// anchored top-left, so the green reads as ambient light in the room rather
/// than as a decorative gradient.
struct GMCanvas: View {
    var body: some View {
        ZStack {
            GMTheme.background
            RadialGradient(
                colors: [GMTheme.green4.opacity(0.10), .clear],
                center: UnitPoint(x: 0.12, y: -0.05),
                startRadius: 0,
                endRadius: 420
            )
            GMGridBackground()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Panel

/// The single container primitive. A flat surface, a hairline frame, and an
/// optional header rail: a 2px green tick followed by an uppercase label.
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
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(GMTheme.accent)
                        .frame(width: 2, height: 11)
                    Text(title).gmMicroLabel(10, color: GMTheme.textSecondary)
                    Spacer(minLength: 8)
                    accessory
                }
                .padding(.horizontal, padding)
                .padding(.vertical, 10)

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
    }
}

// MARK: - Data row

/// One label/value line. The label is a micro label on the left, the value is
/// monospaced and right-aligned, so a stack of rows forms a readable column.
struct GMDataRow: View {
    let label: LocalizedStringKey
    let value: String
    var valueColor: Color = GMTheme.textPrimary
    var mono: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).gmMicroLabel(10)
            Spacer(minLength: 8)
            Text(value)
                .font(mono ? GMTheme.mono(13) : GMTheme.ui(13, .medium))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Chip / tag

/// A bordered monospace chip: plate numbers, RES codes, counts.
struct GMChip: View {
    let text: String
    var tint: Color = GMTheme.accentBright
    var size: CGFloat = 13

    var body: some View {
        Text(text)
            .font(GMTheme.mono(size, .semibold))
            .tracking(0.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
            .gmBorder(tint.opacity(0.30), radius: GMTheme.radiusTight)
    }
}

// MARK: - Status dot

/// Small square status indicator. Square, not round — it reads as a state LED
/// on an instrument panel rather than as a notification bubble.
struct GMStatusDot: View {
    var color: Color = GMTheme.accent
    var size: CGFloat = 6
    var pulsing: Bool = false

    @State private var on = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.9), radius: 3)
            .opacity(pulsing && on ? 0.35 : 1)
            .animation(
                pulsing ? .easeInOut(duration: 0.95).repeatForever(autoreverses: true) : .default,
                value: on
            )
            .onAppear { if pulsing { on = true } }
    }
}

// MARK: - Icon frame

/// Square, hairline-framed glyph holder. Replaces the old circular badge —
/// circles are soft, squares belong to this system.
struct GMIconFrame: View {
    let systemName: String
    var tint: Color = GMTheme.accent
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                .fill(tint.opacity(0.12))
            RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: GMTheme.hairline)
            Image(systemName: systemName)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

/// Kept for older call sites; now renders the square frame.
struct GMIconBadge: View {
    let systemName: String
    var tint: Color = GMTheme.accent
    var size: CGFloat = 34

    var body: some View {
        GMIconFrame(systemName: systemName, tint: tint, size: size)
    }
}

// MARK: - Buttons

/// Filled green action. Sharp corners, hairline lift, uppercase tracked label.
///
/// Disabled does *not* mean "the same button, faded" — a translucent green fill
/// with dark text is unreadable. Disabled renders as an inert recessed slab so
/// the control still reads as a control, just an unavailable one.
struct GMPrimaryButtonStyle: ButtonStyle {
    var color: Color = GMTheme.accent
    var height: CGFloat = 46

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
                .font(.system(size: 13, weight: .bold))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(isEnabled ? Color(hex: 0x08120C) : GMTheme.textFaint)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    isEnabled
                        ? (configuration.isPressed ? color.opacity(0.78) : color)
                        : GMTheme.surfaceInset
                )
                .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous)
                        .strokeBorder(
                            isEnabled ? .white.opacity(0.18) : GMTheme.border,
                            lineWidth: GMTheme.hairline
                        )
                )
                .animation(.easeOut(duration: 0.12), value: isEnabled)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/// Outlined action — the secondary tier. Used for destructive/utility calls
/// that must not compete with the green primary.
struct GMGhostButtonStyle: ButtonStyle {
    var color: Color = GMTheme.textSecondary
    var height: CGFloat = 46

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(configuration.isPressed ? GMTheme.surfaceRaised : GMTheme.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous)
                    .strokeBorder(color.opacity(0.35), lineWidth: GMTheme.hairline)
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Legacy card (thin wrapper over GMPanel)

/// Older screens still build `GMCard { ... }`; it now renders a headerless panel.
struct GMCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GMPanel {
            content
        }
    }
}
