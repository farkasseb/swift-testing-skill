// Behavioral checks for claims the documentation makes about the samples.
import Foundation
import Testing

@Suite struct AwaitCallbackBehavior {
    @Test func returnsTheCallbackValue() async throws {
        let value = try await awaitCallback(timeout: .seconds(5)) { done in
            DispatchQueue.global().async { done(7) }
        }
        #expect(value == 7)
    }

    @Test func timesOutWhenTheCallbackNeverFires() async {
        let start = ContinuousClock.now
        await #expect(throws: CallbackTimedOut.self) {
            _ = try await awaitCallback(timeout: .milliseconds(100)) { (_: @escaping @Sendable (Int) -> Void) in }
        }
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func throwsCancellationErrorWhenCancelled() async {
        let task = Task {
            try await awaitCallback(timeout: .seconds(60)) { (_: @escaping @Sendable (Int) -> Void) in }
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test func handlesCancellationBeforeTheContinuationExists() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await awaitCallback(timeout: .seconds(60)) { (_: @escaping @Sendable (Int) -> Void) in }
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test func ignoresASecondCallback() async throws {
        let value = try await awaitCallback(timeout: .seconds(5)) { done in
            done(1)
            done(2)
        }
        #expect(value == 1)
    }

    @Test func ignoresACallbackAfterTimeout() async throws {
        let stored = Locked<(@Sendable (Int) -> Void)?>(nil)
        await #expect(throws: CallbackTimedOut.self) {
            _ = try await awaitCallback(timeout: .milliseconds(50)) { done in
                stored.withLock { $0 = done }
            }
        }
        stored.withLock { $0 }?(3)   // must not crash
    }
}

// A recursive scoping trait on a suite gives every test case its own database.
let seenDatabases = Locked(Set<Int>())

@Suite(.temporaryDatabase) struct RecursiveScopingBehavior {
    func claimOwnDatabase() throws {
        let database = try #require(TestDatabase.current)
        let isNew = seenDatabases.withLock { $0.insert(database.serial).inserted }
        #expect(isNew, "database shared between test cases")
    }

    @Test func first() throws { try claimOwnDatabase() }
    @Test func second() throws { try claimOwnDatabase() }
    @Test(arguments: [1, 2]) func perCase(n: Int) throws { try claimOwnDatabase() }
}

@Test func scopeTearsDownWhenTheTestThrows() async throws {
    struct Boom: Error {}
    let test = try #require(Test.current)
    let captured = Locked<Database?>(nil)
    await #expect(throws: Boom.self) {
        try await TemporaryDatabaseTrait().provideScope(for: test, testCase: nil) {
            captured.withLock { $0 = TestDatabase.current }
            throw Boom()
        }
    }
    let database = try #require(captured.withLock { $0 })
    #expect(database.isDestroyed)
}
