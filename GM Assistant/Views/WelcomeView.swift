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
            GMTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    promoBanner
                    inputCard
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 40)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onTapGesture { focusedField = nil }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(GMTheme.accent.opacity(0.14))
                    .frame(width: 84, height: 84)
                Image(systemName: "car.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(GMTheme.accent)
            }
            Text("GM Assistant")
                .font(GMTheme.titleFont(28))
                .foregroundStyle(GMTheme.textPrimary)
            Text("welcome_subtitle")
                .font(GMTheme.bodyFont(15))
                .foregroundStyle(GMTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Promo banner

    private var promoBanner: some View {
        Button {
            copyPromoCode()
        } label: {
            ZStack {
                GMTheme.heroGradient
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 160, height: 160)
                    .offset(x: 110, y: -40)
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 100, height: 100)
                    .offset(x: -120, y: 40)

                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("promo_title")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                        Text("promo_subtitle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    Spacer(minLength: 8)

                    VStack(spacing: 2) {
                        Text(promoCopied ? "copied" : "ZURICH23")
                            .font(.system(size: 15, weight: .heavy, design: .monospaced))
                            .foregroundStyle(GMTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        if !promoCopied {
                            Text("tap_to_copy")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: GMTheme.cardCornerRadius, style: .continuous))
        .shadow(color: GMTheme.accent.opacity(0.35), radius: 14, x: 0, y: 8)
        .scaleEffect(promoCopied ? 0.98 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: promoCopied)
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

    // MARK: - Input card

    private var inputCard: some View {
        GMCard {
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
                .font(GMTheme.bodyFont(12))
                .foregroundStyle(GMTheme.textSecondary)

            if appState.isResolving {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("looking_up")
                        .font(GMTheme.bodyFont(13))
                        .foregroundStyle(GMTheme.textSecondary)
                }
                .padding(.top, 2)
            }

            if let error = appState.lookupError {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(LocalizedStringKey(error.messageKey))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(GMTheme.bodyFont(14))
                    .foregroundStyle(GMTheme.danger)

                    if error == .tooManyAttempts {
                        Button {
                            Haptics.light()
                            callRoadside()
                        } label: {
                            Label("roadside_assistance", systemImage: "wrench.and.screwdriver.fill")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
                .padding(.top, 4)
            }

            Button {
                submit(auto: false)
            } label: {
                if appState.isResolving {
                    ProgressView().tint(.white)
                } else {
                    Text("find_reservation")
                }
            }
            .buttonStyle(GMPrimaryButtonStyle())
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.5)
            .padding(.top, 4)

            Text("res_code_hint")
                .font(GMTheme.bodyFont(13))
                .foregroundStyle(GMTheme.textSecondary)
        }
    }

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
        HStack {
            Text(labelKey)
                .font(GMTheme.labelFont(13))
                .foregroundStyle(GMTheme.textSecondary)
                .textCase(.uppercase)
            if isValid {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GMTheme.accent)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isValid)
        .padding(.top, field == .plate ? 6 : 0)

        TextField(placeholder, text: text)
            .font(.system(size: 24, weight: .bold, design: .monospaced))
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
            .padding(14)
            .background(GMTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isValid ? GMTheme.accent.opacity(0.5) : .clear, lineWidth: 1.5)
            )
            .onChange(of: text.wrappedValue) { _, newValue in
                let filtered = sanitize(newValue)
                if filtered != newValue {
                    text.wrappedValue = filtered
                } else {
                    scheduleAutoSubmitIfReady()
                }
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
}
