//
//  WelcomeView.swift
//  GM Assistant
//
//  RES code + plate confirmation — the customer's entry step. Both
//  fields are required: the plate fragment is a second factor only the
//  actual renter knows, so a bare RES code (short and sequential) can't
//  be used to browse other customers' reservations. Submission is
//  automatic the instant both fields become valid — no extra tap needed
//  on the happy path, the button stays only as a manual fallback.
//
//  Presented as a terminal: masthead, link status, then a single
//  authentication panel.
//

import SwiftUI
import UIKit

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @State private var resCode = ""
    @State private var plateSuffix = ""
    @FocusState private var focusedField: Field?
    @State private var autoSubmitTask: Task<Void, Never>?
    @State private var didAutoSubmitFor: String = ""
    @State private var promoCopied = false

    private enum Field {
        case res, plate
    }

    private var resValid: Bool {
        resCode.rangeOfCharacter(from: .decimalDigits) != nil
    }

    private var plateValid: Bool {
        plateSuffix.count >= 3
    }

    private var canSubmit: Bool {
        resValid && plateValid && !appState.isResolving
    }

    var body: some View {
        ZStack {
            GMCanvas()
            ScrollView {
                VStack(spacing: 14) {
                    masthead
                    linkStatus
                    authPanel
                    offerPanel
                    footerMark
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 36)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onTapGesture { focusedField = nil }
    }

    // MARK: - Masthead

    private var masthead: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(GMTheme.accent)
                .frame(width: 3, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: "GM ASSISTANT")
                    .font(.system(size: 25, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(GMTheme.textPrimary)

                Text("welcome_subtitle")
                    .font(GMTheme.ui(12.5))
                    .foregroundStyle(GMTheme.textMuted)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "car.side.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(GMTheme.accent.opacity(0.55))
                .padding(.top, 2)
        }
        .padding(.bottom, 2)
    }

    // MARK: - Link status strip

    private var linkStatus: some View {
        HStack(spacing: 10) {
            GMStatusDot(color: GMTheme.accent, size: 6, pulsing: true)
            Text(verbatim: "SECURE LINK")
                .gmMicroLabel(9, color: GMTheme.textSecondary)

            Rectangle()
                .fill(GMTheme.border)
                .frame(width: GMTheme.hairline, height: 11)

            Text(verbatim: "ZRH · CH")
                .font(GMTheme.mono(10, .semibold))
                .foregroundStyle(GMTheme.textMuted)

            Spacer(minLength: 0)

            Text(verbatim: "v1.0")
                .font(GMTheme.mono(10))
                .foregroundStyle(GMTheme.textFaint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(GMTheme.surface.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
        .gmBorder()
    }

    // MARK: - Authentication panel

    private var authPanel: some View {
        GMPanel("identify_label", spacing: 14) {
            entryField(
                labelKey: "res_code_label",
                placeholder: "RES-12345",
                text: $resCode,
                field: .res,
                isValid: resValid,
                keyboard: .numbersAndPunctuation,
                nextField: .plate
            ) { newValue in
                newValue.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
            }

            entryField(
                labelKey: "plate_suffix_label",
                placeholder: "XYZ",
                text: $plateSuffix,
                field: .plate,
                isValid: plateValid,
                keyboard: .asciiCapable,
                nextField: nil
            ) { newValue in
                String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(8))
            }

            Text("plate_suffix_hint")
                .font(GMTheme.ui(11.5))
                .foregroundStyle(GMTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if appState.isResolving {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(GMTheme.accent)
                    Text("looking_up")
                        .gmMicroLabel(9.5, color: GMTheme.accentBright)
                }
            }

            if let error = appState.lookupError {
                errorBlock(error)
            }

            Button {
                submit(auto: false)
            } label: {
                if appState.isResolving {
                    ProgressView().tint(Color(hex: 0x08120C))
                } else {
                    Text("find_reservation")
                }
            }
            .buttonStyle(GMPrimaryButtonStyle())
            .disabled(!canSubmit)

            Text("res_code_hint")
                .font(GMTheme.ui(11.5))
                .foregroundStyle(GMTheme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        } accessory: {
            HStack(spacing: 5) {
                GMStatusDot(
                    color: canSubmit ? GMTheme.accent : GMTheme.textFaint,
                    size: 5
                )
                Text(verbatim: canSubmit ? "READY" : "AWAITING INPUT")
                    .gmMicroLabel(8.5, color: canSubmit ? GMTheme.accentBright : GMTheme.textFaint)
            }
            .animation(.easeOut(duration: 0.15), value: canSubmit)
        }
    }

    @ViewBuilder
    private func errorBlock(_ error: AppState.LookupError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Rectangle()
                    .fill(GMTheme.danger)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "FAULT")
                        .gmMicroLabel(8.5, color: GMTheme.danger)
                    Text(LocalizedStringKey(error.messageKey))
                        .font(GMTheme.ui(12.5))
                        .foregroundStyle(GMTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if error == .tooManyAttempts {
                Button {
                    Haptics.light()
                    callRoadside()
                } label: {
                    Label("roadside_assistance", systemImage: "wrench.and.screwdriver.fill")
                }
                .buttonStyle(GMGhostButtonStyle(color: GMTheme.danger, height: 40))
            }
        }
        .padding(11)
        .background(GMTheme.danger.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
        .gmBorder(GMTheme.danger.opacity(0.28), radius: GMTheme.radiusTight)
    }

    // MARK: - Entry field

    @ViewBuilder
    private func entryField(
        labelKey: LocalizedStringKey,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        isValid: Bool,
        keyboard: UIKeyboardType,
        nextField: Field?,
        sanitize: @escaping (String) -> String
    ) -> some View {
        let focused = focusedField == field
        let railColor = isValid ? GMTheme.accent
            : (focused ? GMTheme.accentBright.opacity(0.7) : GMTheme.border)

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(labelKey).gmMicroLabel(9.5)
                Spacer(minLength: 8)
                if isValid {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .black))
                        Text(verbatim: "OK")
                            .gmMicroLabel(8.5, color: GMTheme.accentBright)
                    }
                    .foregroundStyle(GMTheme.accentBright)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: isValid)

            HStack(spacing: 0) {
                Rectangle()
                    .fill(railColor)
                    .frame(width: 2)

                TextField("", text: text, prompt:
                    Text(placeholder)
                        .font(GMTheme.mono(19, .medium))
                        .foregroundColor(GMTheme.textFaint)
                )
                .font(GMTheme.mono(19, .semibold))
                .tracking(1.2)
                .foregroundStyle(isValid ? GMTheme.accentBright : GMTheme.textPrimary)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
                .submitLabel(nextField == nil ? .go : .next)
                .onSubmit {
                    if let nextField {
                        focusedField = nextField
                    } else {
                        submit(auto: false)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 13)
                .onChange(of: text.wrappedValue) { _, newValue in
                    let filtered = sanitize(newValue)
                    if filtered != newValue {
                        text.wrappedValue = filtered
                    } else {
                        scheduleAutoSubmitIfReady()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GMTheme.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
            .gmBorder(
                focused ? GMTheme.accent.opacity(0.55) : GMTheme.border,
                radius: GMTheme.radiusTight
            )
            .animation(.easeOut(duration: 0.15), value: focused)
            .animation(.easeOut(duration: 0.15), value: isValid)
        }
    }

    // MARK: - Offer

    private var offerPanel: some View {
        Button {
            copyPromoCode()
        } label: {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(GMTheme.accent)
                    .frame(width: 2, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text("promo_title")
                        .gmMicroLabel(9.5, color: GMTheme.accentBright)
                    Text("promo_subtitle")
                        .font(GMTheme.ui(11.5))
                        .foregroundStyle(GMTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    GMChip(text: promoCopied ? String(localized: "copied") : "ZURICH23")
                    if !promoCopied {
                        Text("tap_to_copy")
                            .gmMicroLabel(8, color: GMTheme.textFaint)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(GMTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
            .gmBorder(promoCopied ? GMTheme.accent.opacity(0.5) : GMTheme.border)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: promoCopied)
    }

    private var footerMark: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(GMTheme.border)
                .frame(height: GMTheme.hairline)
            Text(verbatim: "GREEN MOTION · ZÜRICH")
                .gmMicroLabel(8, color: GMTheme.textFaint)
                .fixedSize()
            Rectangle()
                .fill(GMTheme.border)
                .frame(height: GMTheme.hairline)
        }
        .padding(.top, 6)
    }

    private func copyPromoCode() {
        Haptics.light()
        UIPasteboard.general.string = "ZURICH23"
        withAnimation { promoCopied = true }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            if let url = URL(string: "https://greenmotion.com/de/locations/switzerland/zurich-airport") {
                _ = await UIApplication.shared.open(url)
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation { promoCopied = false }
        }
    }

    // MARK: - Submit

    /// Fires automatically ~350ms after the last keystroke once both
    /// fields are valid — the customer just types and lands inside, no
    /// button tap required on the happy path.
    private func scheduleAutoSubmitIfReady() {
        autoSubmitTask?.cancel()
        guard canSubmit else { return }
        let key = "\(resCode)|\(plateSuffix)"
        guard key != didAutoSubmitFor else { return }
        autoSubmitTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            didAutoSubmitFor = key
            submit(auto: true)
        }
    }

    private func submit(auto: Bool) {
        guard canSubmit else { return }
        autoSubmitTask?.cancel()
        Haptics.light()
        focusedField = nil
        Task {
            await appState.resolveReservation(resCode: resCode, plateSuffix: plateSuffix)
            if appState.lookupError != nil { Haptics.error() } else { Haptics.success() }
        }
    }

    /// Static fallback number so a locked-out customer can still reach
    /// help even before their reservation resolves (which is where the
    /// franchise-specific roadside number normally comes from).
    private func callRoadside() {
        guard let url = URL(string: "tel://+41765373407") else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    WelcomeView()
        .environment(AppState())
        .preferredColorScheme(.dark)
}
