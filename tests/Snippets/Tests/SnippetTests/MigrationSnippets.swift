// Samples from references/migration.md.
import Foundation
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

final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var early: Result<Value, any Error>?
    private var finished = false

    func install(_ continuation: CheckedContinuation<Value, any Error>) {
        lock.lock()
        if let early {
            lock.unlock()
            continuation.resume(with: early)   // cancelled or timed out first
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func resume(with result: Result<Value, any Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }   // later calls are ignored
        finished = true
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            early = result
            lock.unlock()
        }
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
