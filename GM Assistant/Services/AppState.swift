//
//  AppState.swift
//  GM Assistant
//
//  Session state: anonymous auth bootstrap, resolved reservation
//  (persisted so the customer doesn't retype the RES code + plate),
//  and the live customer-record service for the active reservation.
//

import Foundation
import Observation
import FirebaseAuth

@Observable
@MainActor
final class AppState {
    private(set) var reservation: CustomerReservation?
    private(set) var recordService: CustomerRecordService?
    var isResolving = false
    var lookupError: LookupError?

    enum LookupError: Equatable {
        case notFound
        case tooManyAttempts
        case network
        case unknown

        var messageKey: String {
            switch self {
            case .notFound: return "reservation_not_found"
            case .tooManyAttempts: return "too_many_attempts"
            case .network: return "error_network"
            case .unknown: return "error_unknown"
            }
        }
    }

    private static let storedReservationKey = "gm.customer.reservation"
    /// Plate suffix kept alongside the reservation purely to silently
    /// refresh the session (phone config, TTL) on relaunch — not sensitive,
    /// it's printed on the vehicle itself.
    private static let storedPlateSuffixKey = "gm.customer.plateSuffix"

    /// Signs in anonymously (if needed) and restores the persisted session.
    func bootstrap() async {
        do {
            if Auth.auth().currentUser == nil {
                _ = try await Auth.auth().signInAnonymously()
            }
        } catch {
            print("Anonymous sign-in failed: \(error.localizedDescription)")
        }
        restorePersistedReservation()
    }

    func resolveReservation(resCode: String, plateSuffix: String) async {
        let trimmedRes = resCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPlate = plateSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRes.isEmpty, !trimmedPlate.isEmpty else { return }
        isResolving = true
        lookupError = nil
        defer { isResolving = false }

        do {
            if Auth.auth().currentUser == nil {
                _ = try await Auth.auth().signInAnonymously()
            }
            let resolved = try await ReservationService.resolve(
                resCode: trimmedRes,
                plateSuffix: trimmedPlate
            )
            setReservation(resolved, plateSuffix: trimmedPlate)
        } catch let error as ReservationService.ServiceError {
            switch error {
            case .notFound: lookupError = .notFound
            case .tooManyAttempts: lookupError = .tooManyAttempts
            case .invalidResponse: lookupError = .unknown
            }
        } catch {
            let ns = error as NSError
            lookupError = ns.domain == NSURLErrorDomain ? .network : .unknown
        }
    }

    func endSession() {
        recordService?.stop()
        recordService = nil
        reservation = nil
        UserDefaults.standard.removeObject(forKey: Self.storedReservationKey)
        UserDefaults.standard.removeObject(forKey: Self.storedPlateSuffixKey)
    }

    private func setReservation(_ newValue: CustomerReservation, plateSuffix: String) {
        reservation = newValue
        if let data = try? JSONEncoder().encode(newValue) {
            UserDefaults.standard.set(data, forKey: Self.storedReservationKey)
        }
        UserDefaults.standard.set(plateSuffix, forKey: Self.storedPlateSuffixKey)
        startRecordService(for: newValue)
    }

    private func restorePersistedReservation() {
        guard reservation == nil,
              let data = UserDefaults.standard.data(forKey: Self.storedReservationKey),
              let stored = try? JSONDecoder().decode(CustomerReservation.self, from: data)
        else { return }
        reservation = stored
        startRecordService(for: stored)
        // Refresh the session server-side (session doc TTL, phone config
        // updates). Failure is fine — the persisted copy keeps working.
        guard let plateSuffix = UserDefaults.standard.string(forKey: Self.storedPlateSuffixKey),
              !plateSuffix.isEmpty else { return }
        Task {
            if let refreshed = try? await ReservationService.resolve(
                resCode: stored.resKodu,
                plateSuffix: plateSuffix
            ) {
                reservation = refreshed
                if let data = try? JSONEncoder().encode(refreshed) {
                    UserDefaults.standard.set(data, forKey: Self.storedReservationKey)
                }
                recordService?.update(reservation: refreshed)
            }
        }
    }

    private func startRecordService(for reservation: CustomerReservation) {
        recordService?.stop()
        let service = CustomerRecordService(reservation: reservation)
        service.start()
        recordService = service
    }
}
