// Samples from references/migration.md.
import Foundation
import os
import Testing

struct CallbackTimedOut: Error {}

func awaitCallback<Value: Sendable>(
    timeout: Duration,
    _ start: (@escaping @Sendable (Value) -> Void) -> Void
) async throws -> Value {
    let once = ResumeOnce<Value>()
    let timer = Task {
        try await Task.sleep(for: timeout)
        once.resume(with: .failure(CallbackTimedOut()))
    }
    defer { timer.cancel() }
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            once.install(continuation)
            start { value in once.resume(with: .success(value)) }
        }
    } onCancel: {
        once.resume(with: .failure(CancellationError()))
    }
}

final class ResumeOnce<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, any Error>?
        var early: Result<Value, any Error>?
        var finished = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func install(_ continuation: CheckedContinuation<Value, any Error>) {
        let early = state.withLock { state in
            if state.early == nil { state.continuation = continuation }
            return state.early
        }
        if let early { continuation.resume(with: early) }   // cancelled or timed out first
    }

    func resume(with result: Result<Value, any Error>) {
        let continuation = state.withLock { state -> CheckedContinuation<Value, any Error>? in
            guard !state.finished else { return nil }   // later calls are ignored
            state.finished = true
            guard let continuation = state.continuation else {
                state.early = result
                return nil
            }
            state.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}

@Test func completionHandlerMigration() async throws {
    let result = try await awaitCallback(timeout: .seconds(10)) { done in
        sut.load(completion: done)
    }
    #expect(try result.get() == 42)
}

@Test func asyncLetRelease() async {
    let gate = Gate()
    let sut = FeatureService(gate: gate)
    async let enabled = sut.isEnabled()
    gate.open()
    #expect(await enabled)
}

func expectValid(
    _ order: Order,
    sourceLocation: SourceLocation = SourceLocation(
        fileID: #fileID, filePath: #filePath, line: #line, column: #column
    )
) {
    #expect(order.total >= 0, sourceLocation: sourceLocation)
    #expect(!order.items.isEmpty, sourceLocation: sourceLocation)
}

@Test func helperForwardsLocation() { expectValid(Order()) }

@Test func projectHelperTranslations() async {
    // helper(expression, expectedError)  →  exact value (this client throws .badRequest)
    await withKnownIssue {
        await #expect(throws: APIError.unauthorized) { try await client.fetch() }
    }

    // helper(expression) { error in guard case .badRequest(let body) = error as? APIError … }
    let error = await #expect(throws: (any Error).self) { try await client.fetch() }
    guard case .badRequest(let body) = error as? APIError else {
        Issue.record("Expected .badRequest, got \(String(describing: error))")
        return
    }
    #expect(body == expectedBody)
}
