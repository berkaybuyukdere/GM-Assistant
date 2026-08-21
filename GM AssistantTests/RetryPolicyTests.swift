//
//  RetryPolicyTests.swift
//  GM AssistantTests
//
//  Retrying the wrong error is worse than not retrying. The reservation
//  callable answers `resourceExhausted` from a per-IP lockout that counts
//  the customer's failed attempts and locks them out for 30 minutes once the
//  budget is gone — an automatic retry would spend that budget on their
//  behalf. This test exists so nobody "fixes" the classifier by making it
//  more generous.
//

import Testing
import Foundation
import FirebaseFunctions
import FirebaseFirestore
@testable import GM_Assistant

struct RetryPolicyTests {

    private func functionsError(_ code: FunctionsErrorCode) -> NSError {
        NSError(domain: FunctionsErrorDomain, code: code.rawValue)
    }

    private func urlError(_ code: Int) -> NSError {
        NSError(domain: NSURLErrorDomain, code: code)
    }

    // MARK: - Must never retry

    @Test func rateLimitIsNeverRetried() {
        #expect(GMRetry.isTransient(functionsError(.resourceExhausted)) == false)
    }

    @Test func definitiveAnswersAreNeverRetried() {
        #expect(GMRetry.isTransient(functionsError(.notFound)) == false)
        #expect(GMRetry.isTransient(functionsError(.permissionDenied)) == false)
        #expect(GMRetry.isTransient(functionsError(.unauthenticated)) == false)
        #expect(GMRetry.isTransient(functionsError(.invalidArgument)) == false)
    }

    @Test func unrelatedDomainsAreNotRetried() {
        #expect(GMRetry.isTransient(NSError(domain: "com.example.other", code: 14)) == false)
        #expect(GMRetry.isTransient(PhotoUploadService.UploadError.notSignedIn) == false)
    }

    // MARK: - Should retry

    @Test func backendUnavailabilityIsRetried() {
        #expect(GMRetry.isTransient(functionsError(.unavailable)))
        #expect(GMRetry.isTransient(functionsError(.deadlineExceeded)))
        #expect(GMRetry.isTransient(functionsError(.internal)))
    }

    @Test func transportFailuresAreRetried() {
        #expect(GMRetry.isTransient(urlError(NSURLErrorTimedOut)))
        #expect(GMRetry.isTransient(urlError(NSURLErrorNetworkConnectionLost)))
        #expect(GMRetry.isTransient(urlError(NSURLErrorNotConnectedToInternet)))
        #expect(GMRetry.isTransient(urlError(NSURLErrorCannotConnectToHost)))
    }

    /// A cancelled request is the user leaving the screen, not a fault.
    @Test func cancellationIsNotRetried() {
        #expect(GMRetry.isTransient(urlError(NSURLErrorCancelled)) == false)
    }

    // MARK: - Runner behaviour

    @Test func returnsTheValueWithoutRetryingOnSuccess() async throws {
        let attempts = Counter()
        let value = try await GMRetry.run(
            context: "test",
            logger: GMLog.session
        ) {
            await attempts.bump()
            return 42
        }
        #expect(value == 42)
        #expect(await attempts.count == 1)
    }

    @Test func retriesTransientFailuresThenSucceeds() async throws {
        let attempts = Counter()
        let value = try await GMRetry.run(
            attempts: 3,
            initialDelay: .milliseconds(1),
            context: "test",
            logger: GMLog.session
        ) {
            let n = await attempts.bump()
            if n < 3 { throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut) }
            return "ok"
        }
        #expect(value == "ok")
        #expect(await attempts.count == 3)
    }

    @Test func givesUpImmediatelyOnANonRetryableError() async {
        let attempts = Counter()
        await #expect(throws: (any Error).self) {
            try await GMRetry.run(
                attempts: 4,
                initialDelay: .milliseconds(1),
                context: "test",
                logger: GMLog.session
            ) {
                _ = await attempts.bump()
                throw NSError(
                    domain: FunctionsErrorDomain,
                    code: FunctionsErrorCode.resourceExhausted.rawValue
                )
            }
        }
        #expect(await attempts.count == 1, "a rate-limit answer must not be retried")
    }

    @Test func stopsAfterTheAttemptBudgetIsSpent() async {
        let attempts = Counter()
        await #expect(throws: (any Error).self) {
            try await GMRetry.run(
                attempts: 3,
                initialDelay: .milliseconds(1),
                context: "test",
                logger: GMLog.session
            ) {
                _ = await attempts.bump()
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
            }
        }
        #expect(await attempts.count == 3)
    }
}

private actor Counter {
    private(set) var count = 0

    @discardableResult
    func bump() -> Int {
        count += 1
        return count
    }
}
