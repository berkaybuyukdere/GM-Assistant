//
//  GMRetry.swift
//  GM Assistant
//
//  Exponential-backoff retry for the network calls the customer actually
//  waits on: reservation lookup, photo upload, and record writes.
//
//  The important half of this file is `isTransient`. Retrying the wrong
//  error is worse than not retrying at all — in particular the reservation
//  callable answers `resourceExhausted` from a server-side rate limiter
//  that counts failed attempts per IP and locks the customer out for 30
//  minutes once the budget is gone. Automatically retrying that would spend
//  the customer's remaining attempts for them. So only errors that mean
//  "the network or the backend was briefly unavailable" are retried;
//  anything that means "your request was answered, and the answer was no"
//  is surfaced immediately.
//

import Foundation
import OSLog
import FirebaseFunctions
import FirebaseFirestore
import FirebaseStorage

enum GMRetry {

    /// Runs `operation`, retrying transient failures with exponential backoff.
    /// The last failure is rethrown once attempts are exhausted.
    static func run<T>(
        attempts: Int = 3,
        initialDelay: Duration = .milliseconds(500),
        context: String,
        logger: Logger,
        isRetryable: (Error) -> Bool = GMRetry.isTransient,
        operation: () async throws -> T
    ) async throws -> T {
        var delay = initialDelay
        var lastError: Error?

        for attempt in 1...max(1, attempts) {
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                let canRetry = attempt < attempts && isRetryable(error)
                guard canRetry else { break }

                logger.notice(
                    "\(context, privacy: .public): attempt \(attempt) failed, retrying — \(error.localizedDescription, privacy: .public)"
                )
                try? await Task.sleep(for: delay)
                if Task.isCancelled { throw CancellationError() }
                delay = delay * 2
            }
        }

        throw lastError ?? CancellationError()
    }

    /// True only for failures that are plausibly momentary.
    static func isTransient(_ error: Error) -> Bool {
        let ns = error as NSError

        switch ns.domain {
        case NSURLErrorDomain:
            return transientURLErrorCodes.contains(ns.code)

        case FunctionsErrorDomain:
            switch FunctionsErrorCode(rawValue: ns.code) {
            case .unavailable, .deadlineExceeded, .internal, .aborted:
                return true
            default:
                // Explicitly includes .resourceExhausted (the lookup rate
                // limiter), .notFound, .permissionDenied, .unauthenticated.
                return false
            }

        case FirestoreErrorDomain:
            switch FirestoreErrorCode.Code(rawValue: ns.code) {
            case .unavailable, .deadlineExceeded, .internal, .aborted:
                return true
            default:
                return false
            }

        case StorageErrorDomain:
            // The Storage SDK already retries internally; `retryLimitExceeded`
            // means those attempts ran out, which on a flaky mobile connection
            // is still worth one more try behind a longer backoff.
            return StorageErrorCode(rawValue: ns.code) == .retryLimitExceeded

        default:
            return false
        }
    }

    private static let transientURLErrorCodes: Set<Int> = [
        NSURLErrorTimedOut,
        NSURLErrorCannotFindHost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorDNSLookupFailed,
        NSURLErrorNotConnectedToInternet,
        NSURLErrorResourceUnavailable,
        NSURLErrorSecureConnectionFailed,
    ]
}
