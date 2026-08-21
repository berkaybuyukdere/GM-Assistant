//
//  ReservationService.swift
//  GM Assistant
//
//  Calls the `customerResolveReservation` Cloud Function (us-central1).
//  Requires BOTH the RES code and the last characters of the vehicle's
//  plate — a second factor only the actual renter has, so the RES code
//  alone (short, sequential) can't be used to browse other customers'
//  reservations. The function validates server-side, registers the
//  anonymous customer session and returns a whitelisted summary.
//

import Foundation
import FirebaseFunctions

enum ReservationService {
    enum ServiceError: Error {
        case notFound
        case tooManyAttempts
        case invalidResponse
    }

    private static let functions = Functions.functions(region: "us-central1")

    static func resolve(resCode: String, plateSuffix: String) async throws -> CustomerReservation {
        do {
            // Retries only genuinely transient failures. A `resourceExhausted`
            // answer is the server's per-IP lockout counting the customer's
            // failed attempts — retrying it would spend their remaining budget,
            // so `GMRetry.isTransient` deliberately excludes it.
            return try await GMRetry.run(
                context: "resolve reservation",
                logger: GMLog.session
            ) {
                let result = try await functions
                    .httpsCallable("customerResolveReservation")
                    .call(["resCode": resCode, "plateSuffix": plateSuffix])
                guard
                    let data = result.data as? [String: Any],
                    let reservation = CustomerReservation(callableData: data)
                else {
                    throw ServiceError.invalidResponse
                }
                return reservation
            }
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            switch FunctionsErrorCode(rawValue: error.code) {
            case .notFound: throw ServiceError.notFound
            case .resourceExhausted: throw ServiceError.tooManyAttempts
            default: throw error
            }
        }
    }
}
