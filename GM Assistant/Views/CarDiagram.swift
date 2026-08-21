//
//  CarDiagram.swift
//  GM Assistant
//
//  Top-down car used as the backdrop of the walk-around map.
//
//  Drawn rather than shipped as an image on purpose: the reference photo is
//  a white car, which would vanish against a white panel and again against a
//  dark one. A drawn schematic keeps its contrast in both themes, scales to
//  any marker layout without resampling, and adds nothing to the bundle.
//  It is a diagram, not a portrait — the customer needs to read "this is the
//  front left corner", not admire the paint.
//

import SwiftUI

/// Rounded, slightly tapered silhouette seen from above. Nose at the top.
struct CarTopDownShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        var path = Path()
        path.move(to: p(0.50, 0.00))
        // Nose → right front corner
        path.addCurve(to: p(0.96, 0.19), control1: p(0.79, 0.004), control2: p(0.93, 0.07))
        // Right flank, widest around the doors
        path.addCurve(to: p(1.00, 0.52), control1: p(0.99, 0.29), control2: p(1.00, 0.41))
        path.addCurve(to: p(0.95, 0.87), control1: p(1.00, 0.67), control2: p(0.99, 0.79))
        // Rear right corner → tail
        path.addCurve(to: p(0.50, 1.00), control1: p(0.92, 0.97), control2: p(0.73, 1.00))
        // Mirror image back up the left flank
        path.addCurve(to: p(0.05, 0.87), control1: p(0.27, 1.00), control2: p(0.08, 0.97))
        path.addCurve(to: p(0.00, 0.52), control1: p(0.01, 0.79), control2: p(0.00, 0.67))
        path.addCurve(to: p(0.04, 0.19), control1: p(0.00, 0.41), control2: p(0.01, 0.29))
        path.addCurve(to: p(0.50, 0.00), control1: p(0.07, 0.07), control2: p(0.21, 0.004))
        path.closeSubpath()
        return path
    }
}

struct CarDiagram: View {

    private static let body = Color(light: Color(hex: 0xD4DEE6), dark: Color(hex: 0x2B323A))
    private static let glass = Color(light: Color(hex: 0x8FA3B4), dark: Color(hex: 0x161B21))
    private static let roof = Color(light: Color(hex: 0xC3D0DA), dark: Color(hex: 0x333B44))
    private static let rubber = Color(light: Color(hex: 0x6C7986), dark: Color(hex: 0x0C1015))
    private static let lamp = Color(light: Color(hex: 0xF2C14E), dark: Color(hex: 0xC79A32))

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                CarTopDownShape()
                    .fill(Self.body)
                CarTopDownShape()
                    .stroke(GMTheme.borderStrong, lineWidth: 1)

                // Tyres, drawn over the flanks. From directly above this is
                // all you actually see of a wheel — a dark band at the arch.
                ForEach(Array(wheelCentres.enumerated()), id: \.offset) { _, centre in
                    RoundedRectangle(cornerRadius: w * 0.025, style: .continuous)
                        .fill(Self.rubber)
                        .frame(width: w * 0.10, height: h * 0.105)
                        .position(x: centre.x * w, y: centre.y * h)
                }

                // Headlights and tail lights — orientation cues, so nobody has
                // to guess which end of the diagram is the front.
                ForEach([0.30, 0.70], id: \.self) { x in
                    Capsule()
                        .fill(Self.lamp.opacity(0.85))
                        .frame(width: w * 0.16, height: h * 0.022)
                        .position(x: x * w, y: h * 0.055)
                }
                ForEach([0.31, 0.69], id: \.self) { x in
                    Capsule()
                        .fill(GMTheme.danger.opacity(0.65))
                        .frame(width: w * 0.15, height: h * 0.02)
                        .position(x: x * w, y: h * 0.955)
                }

                // Cabin: one dark glass mass with the roof panel inside it,
                // which reads as windscreen + roof + rear window.
                RoundedRectangle(cornerRadius: w * 0.10, style: .continuous)
                    .fill(Self.glass)
                    .frame(width: w * 0.78, height: h * 0.44)
                    .position(x: w * 0.5, y: h * 0.485)

                RoundedRectangle(cornerRadius: w * 0.07, style: .continuous)
                    .fill(Self.roof)
                    .frame(width: w * 0.68, height: h * 0.235)
                    .position(x: w * 0.5, y: h * 0.49)

                // Wing mirrors
                ForEach([0.055, 0.945], id: \.self) { x in
                    Capsule()
                        .fill(Self.body)
                        .overlay(Capsule().stroke(GMTheme.borderStrong, lineWidth: 0.75))
                        .frame(width: w * 0.09, height: h * 0.022)
                        .position(x: x * w, y: h * 0.315)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var wheelCentres: [CGPoint] {
        [
            CGPoint(x: 0.055, y: 0.285), CGPoint(x: 0.945, y: 0.285),
            CGPoint(x: 0.055, y: 0.715), CGPoint(x: 0.945, y: 0.715),
        ]
    }
}

#Preview {
    CarDiagram()
        .frame(width: 150, height: 300)
        .padding(40)
}
