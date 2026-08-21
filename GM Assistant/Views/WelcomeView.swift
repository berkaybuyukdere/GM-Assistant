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
//  This is the first screen anyone sees, so it also carries the
//  partnership line.
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
                VStack(spacing: 16) {
                    masthead
                    partnershipStrip
                    authPanel
                    offerPanel
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, 40)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onTapGesture { focusedField = nil }
    }

    // MARK: - Masthead

    private var masthead: some View {
        HStack(alignment: .top, spacing: 13) {
            Capsule()
                .fill(GMTheme.accent)
                .frame(width: 3.5, height: 46)

            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "GM Assistant")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(GMTheme.textPrimary)

                Text("welcome_subtitle")
                    .font(GMTheme.ui(13.5))
                    .foregroundStyle(GMTheme.textMuted)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "car.side.fill")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(GMTheme.accent.opacity(0.5))
                .padding(.top, 3)
        }
    }

    // MARK: - Partnership

    /// The first thing on the first screen: who this app is run with.
    private var partnershipStrip: some View {
        HStack(spacing: 9) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GMTheme.accent)

            Text("partnership_line")
                .font(GMTheme.ui(12.5, .medium))
                .foregroundStyle(GMTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(GMTheme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
        .gmBorder(GMTheme.accent.opacity(0.22))
    }

    // MARK: - Authentication panel

    private var authPanel: some View {
        GMPanel("identify_label", spacing: 15) {
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
                .gmCaption()
                .fixedSize(horizontal: false, vertical: true)

            if appState.isResolving {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(GMTheme.accent)
                    Text("looking_up")
                        .gmCaption(12.5, color: GMTheme.accentText)
                }
            }

            if let error = appState.lookupError {
                errorBlock(error)
            }

            Button {
                submit(auto: false)
            } label: {
                if appState.isResolving {
                    ProgressView().tint(GMTheme.onAccent)
                } else {
                    Text("find_reservation")
                }
            }
            .buttonStyle(GMPrimaryButtonStyle())
            .disabled(!canSubmit)

            Text("res_code_hint")
                .gmCaption(12, color: GMTheme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func errorBlock(_ error: AppState.LookupError) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GMTheme.danger)
                Text(LocalizedStringKey(error.messageKey))
                    .font(GMTheme.ui(13))
                    .foregroundStyle(GMTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if error == .tooManyAttempts {
                Button {
                    Haptics.light()
                    callRoadside()
                } label: {
                    Label("roadside_assistance", systemImage: "wrench.and.screwdriver.fill")
                }
                .buttonStyle(GMGhostButtonStyle(color: GMTheme.danger, height: 42))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GMTheme.danger.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
        .gmBorder(GMTheme.danger.opacity(0.22), radius: GMTheme.radiusTight)
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

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(labelKey)
                    .font(GMTheme.ui(12.5, .medium))
                    .foregroundStyle(GMTheme.textSecondary)
                Spacer(minLength: 8)
                if isValid {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GMTheme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isValid)

            TextField("", text: text, prompt:
                Text(placeholder)
                    .font(GMTheme.mono(19, .medium))
                    .foregroundColor(GMTheme.textFaint)
            )
            .font(GMTheme.mono(19, .semibold))
            .tracking(1.0)
            .foregroundStyle(GMTheme.textPrimary)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GMTheme.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.radiusTight, style: .continuous))
            .gmBorder(
                focused ? GMTheme.accent.opacity(0.65)
                    : (isValid ? GMTheme.accent.opacity(0.35) : GMTheme.border),
                radius: GMTheme.radiusTight
            )
            .animation(.easeOut(duration: 0.15), value: focused)
            .animation(.easeOut(duration: 0.15), value: isValid)
            .onChange(of: text.wrappedValue) { _, newValue in
                let filtered = sanitize(newValue)
                if filtered != newValue {
                    text.wrappedValue = filtered
                } else {
                    scheduleAutoSubmitIfReady()
                }
            }
        }
    }

    // MARK: - Offer

    private var offerPanel: some View {
        Button {
            copyPromoCode()
        } label: {
            HStack(spacing: 13) {
                GMIconFrame(systemName: "sparkles", size: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text("promo_title")
                        .font(GMTheme.ui(14, .semibold))
                        .foregroundStyle(GMTheme.textPrimary)
                    Text("promo_subtitle")
                        .gmCaption(12)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    GMChip(text: promoCopied ? String(localized: "copied") : GMConfig.promoCode)
                    if !promoCopied {
                        Text("tap_to_copy")
                            .gmCaption(10.5, color: GMTheme.textFaint)
                    }
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity)
            .background(GMTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: GMTheme.radius, style: .continuous))
            .gmBorder(promoCopied ? GMTheme.accent.opacity(0.45) : GMTheme.border)
            .shadow(color: GMTheme.panelShadow, radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: promoCopied)
    }

    private func copyPromoCode() {
        Haptics.light()
        UIPasteboard.general.string = GMConfig.promoCode
        withAnimation { promoCopied = true }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            if let url = GMConfig.promoURL {
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
        guard let url = URL(string: "tel://\(GMConfig.fallbackRoadsidePhone)") else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    WelcomeView()
        .environment(AppState())
}
