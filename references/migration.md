# Migrating from XCTest

Preserve assertion semantics, observation boundaries, and shared-instance sequences. Apple's `modernize-tests` supplies useful mechanical mappings, but its asynchronous `confirmation` rewrite does not wait, and `Codable` alone does not declare `Attachable` conformance. Neither skill replaces checking the actual target's API availability.

Migrate one class at a time. UI tests and `measure { }` tests stay XCTest. When dropping `import XCTest`, add `import Foundation` if the file uses Foundation types, since XCTest re-exported it.

## Mapping

| XCTest | Swift Testing |
|---|---|
| `final class FooTests: XCTestCase` | `struct FooTests` (`final class` or `actor` if it needs `deinit`) |
| `setUp()` / `setUpWithError()` | stored property initializers, or `init() async throws` |
| `tearDown()` | `deinit` (class or actor suite); async or throwing teardown: a `TestScoping` trait |
| `XCTAssert(x)`, `XCTAssertTrue(x)` / `XCTAssertFalse(x)` | `#expect(x)` / `#expect(!x)` |
| `XCTAssertEqual`, `NotEqual`, `GreaterThan`, …, `Nil`, `NotNil`, `Identical` | `#expect(a == b)`, `!=`, `>`, `== nil`, `!= nil`, `===` |
| `XCTAssertEqual(a, b, accuracy: e)` | For finite values and a nonnegative tolerance, `#expect(abs(a - b) <= e)`; preserve any special-value behavior the original test relied on |
| `try XCTUnwrap(x)` | `try #require(x)` |
| `XCTAssertThrowsError(try f())` | `#expect(throws: (any Error).self) { try f() }` |
| `XCTAssertThrowsError(try f()) { error in … }` | `let error = #expect(throws: (any Error).self) { try f() }`, then inspect |
| `XCTAssertNoThrow(try f())` | `#expect(throws: Never.self) { try f() }` |
| `XCTFail("msg")` | `Issue.record("msg")`, or fold into `#expect` / `try #require` |
| `expectation` + `fulfill` + `wait` | see [Completion handlers](#completion-handlers); `confirmation` only for callbacks that fire before its closure returns |
| `XCTSkipIf(c)` / `XCTSkipUnless(c)` | `.disabled(if: c)` / `.enabled(if: c)`; OS checks: `@available` |
| `throw XCTSkip("why")` mid-test | `try Test.cancel("why")` |
| `XCTExpectFailure { }` (`strict: false`) | `withKnownIssue { }` (`isIntermittent: true`) |
| `expectedFulfillmentCount = n` + `assertForOverFulfill = false` | `confirmation(expectedCount: n...)` |
| `XCTAttachment` + `add(_:)` | `Attachment.record(_:named:)` |

Trait conditions are evaluated before the suite instance exists. A skip that read instance state becomes `Test.cancel` inside the test.

Remove the XCTest discovery prefix when adding `@Test`, preserving project naming conventions. Raw identifiers need Swift 6.2; display names work on older toolchains.

## State, setup, and teardown

- Turn implicitly unwrapped `var sut: T!` set in `setUp` into `let sut = T()`, or assign it in `init`.
- A test that mutates a stored property needs `mutating`. A property mutated from an escaping closure cannot stay on a struct suite; move it into a local `var` in the test.
- A `tearDown` that only set properties to `nil` disappears. One that reset static or shared state, removed observers, or restored a singleton becomes a `deinit` on a `final class` or `actor` suite, plus `@Suite(.serialized)`. Check whether other suites touch the same static: serialization is per suite.
- Observation and cancellation tokens held in locals must outlive the assertions. Await the operation first, then assert inside `withExtendedLifetime(tokens) { … }`; do not `await` inside that closure.
- XCTest ran synchronous tests on the main actor, one at a time. Add `@MainActor` only where the test relied on that, and `.serialized` only where tests share mutable state.

## `continueAfterFailure = false`

XCTest stopped at the first failure. Every later assertion in that scope becomes `try #require(...)`, and the test gains `throws`. If it was set in `setUp`, that applies to every test in the class. Do not turn existing `try #require` calls into `#expect`.

## Errors

`XCTAssertThrowsError` did not stop the test, so map it to `#expect(throws:)` and inspect the returned optional. Use `#require(throws:)` only when the test should stop there, for example under `continueAfterFailure = false`. When the error is `Equatable` and the exact value is known, pass the value: `#expect(throws: MyError.notFound) { … }`.

## Completion handlers

The usual XCTest shape (call the SUT, assert inside the callback, fulfill, wait with a timeout) becomes "await the result with the same timeout, then assert outside the callback". Keep the bound. A bare `withCheckedContinuation` waits forever if the callback never fires, and `.timeLimit` only requests cancellation, which does not resume a continuation. Swift Testing has no built-in bounded wait, so add a small adapter to the test target that resumes exactly once, on the first callback, on timeout, or on cancellation:

```swift
import Foundation

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
```

```swift
// XCTest
let exp = expectation(description: "load")
sut.load { result in
    XCTAssertEqual(try? result.get(), 42)
    exp.fulfill()
}
wait(for: [exp], timeout: 10)

// Swift Testing
let result = try await awaitCallback(timeout: .seconds(10)) { done in
    sut.load(completion: done)
}
#expect(try result.get() == 42)
```

A timeout throws `CallbackTimedOut`, which fails the test like the XCTest timeout did. This adapter bounds the wait, not the lifetime of the underlying operation. `start` must return promptly; cancel or unregister the operation separately if it can outlive the test. A second callback is ignored instead of crashing, so this is not an exactly-once assertion. If the original expectation checked over-fulfillment, retain a separate count and await the operation's completion boundary before checking it. If you cannot add a helper like this, keep the test in XCTest rather than drop the bound.

- Multi-shot callbacks (observers, progress): collect values into a local array, await the SUT's own completion point, then assert the count and values.
- `waitForExpectations(timeout: 0)` asserted that the callback ran synchronously. Keep that: store into a local optional and `try #require` it right after the call, with no continuation.
- "Must not fire": `confirmation(expectedCount: 0)` proves nothing unless its body awaits the whole window in which the callback could fire. A spy count checked immediately after the call only covers synchronous behavior. For a delayed forbidden callback, keep the original observation window or await a reliable end-of-operation signal.
- If the XCTest started the call in a `Task` and then released something the call waits on, a direct `await` deadlocks. Start concurrently, wait for a signal that the operation has installed its callback, then release and await. Starting a task alone does not prove it has reached that point. For a gate that remembers an early open, this simpler form suffices:

  ```swift
  async let enabled = sut.isEnabled()
  gate.open()
  #expect(await enabled)
  ```
- A callback test that had no expectation at all could pass vacuously in XCTest. Awaiting it may expose a real failure. Report it; do not weaken the test.

## Helper assertions

Forward the caller's location to every `#expect`, `#require`, and `Issue.record` in the helper. Use the public initializer, never `#_sourceLocation`:

```swift
func expectValid(
    _ order: Order,
    sourceLocation: SourceLocation = SourceLocation(
        fileID: #fileID, filePath: #filePath, line: #line, column: #column
    )
) {
    #expect(order.total >= 0, sourceLocation: sourceLocation)
    #expect(!order.items.isEmpty, sourceLocation: sourceLocation)
}
```

## Project-specific XCTest helpers

Projects often wrap XCTest in their own helpers, for example an async throws-assertion that takes either an expected error value or a predicate closure. These call `XCTAssert*` internally, so they are not safe inside `@Test` (see [XCTest interop](#xctest-interop)). Translate each call with its full meaning:

```swift
// helper(expression, expectedError)  →  exact value
await #expect(throws: APIError.unauthorized) { try await client.fetch() }

// helper(expression) { error in guard case .badRequest(let body) = error as? APIError … }
let error = await #expect(throws: (any Error).self) { try await client.fetch() }
guard case .badRequest(let body) = error as? APIError else {
    Issue.record("Expected .badRequest, got \(String(describing: error))")
    return
}
#expect(body == expectedBody)
```

Never reduce a predicate that checks an associated value to a case-only check, and never cast the error to a different type than the predicate did.

## Test plans

An `.xctestplan` lists skipped XCTest classes as plain strings or under `xctestClasses`, and skipped Swift Testing suites under `suites`:

```json
"skippedTests" : {
  "suites" : [ { "name" : "CheckoutTests" } ],
  "xctestClasses" : [ { "name" : "LegacyTests", "xctestMethods" : [ "testExample()" ] } ]
}
```

A suite that is still listed only in the XCTest shape after migration is no longer skipped, and nothing warns about it. Move the entry to `suites` in every plan that includes the target.

## XCTest interop

Swift 6.4 implements [ST-0021](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0021-targeted-interoperability-swift-testing-and-xctest.md): `XCTAssert*` and `XCTFail` called inside `@Test` are reported to Swift Testing. The following outcomes were run on Xcode 26.6 and 27.1 beta (Testing 1902 and 2084):

| Setup | Mode | `XCTAssert*` failure in `@Test` |
|---|---|---|
| Swift 6.3 or earlier | none | ignored, test passes |
| Package, `swift-tools-version` < 6.4 | limited | warnings, test passes |
| Xcode project (app or framework test target) | limited | warnings, test passes |
| Package, `swift-tools-version` >= 6.4 | complete | test fails |
| Swift 6.4, with `SWIFT_TESTING_XCTEST_INTEROP_MODE=complete` | complete | test fails |

Set the variable in the scheme's test environment or the test plan's environment variables (both verified on Xcode 27.1 beta with an iOS simulator target), or set it in the `xcodebuild` process environment with the forwarding prefix:

```bash
TEST_RUNNER_SWIFT_TESTING_XCTEST_INTEROP_MODE=complete xcodebuild test ...
```

Putting that assignment after `xcodebuild` treats it as a build setting and did not forward it in the simulator probe. Other values: `none`, `limited`, and `strict` (a failing XCTest assertion traps in the installed Xcode libraries; a passing assertion did not trap, so this is not an exhaustive usage detector). ST-0021 also specifies Swift Testing assertion, known-issue and cancellation interoperability in `XCTestCase` methods when interop is enabled; `none` disables this support. It does not cover `XCTestExpectation`, `XCTWaiter`, or traits, and `throw XCTSkip` inside `@Test` is a test failure, not a skip. Interop is a safety net for the migration, not a style.

## Verify the migration

A green run proves little while `XCTAssert*` inside `@Test` passes. Before trusting it:

```bash
rg -n 'XCTAssert|XCTFail|XCTUnwrap|XCTestExpectation|wait\(for|waitForExpectations|fulfill\(\)' <migrated files>
```

Compare test counts per suite before and after (`func test…()` methods then, `@Test` functions and parameterized cases now), and check every migrated suite's skip entries in every test plan.

Counts are an inventory check, not proof of preserved behavior. Compare the assertions and their reachability, including independent checks after an error. Do not replace a sequence on one SUT with fresh-instance parameterized cases unless you also preserve the sequence coverage. Run the original and migrated tests against a representative production mutation when this is the risk being checked.

Sources: [Apple migration guidance](https://developer.apple.com/documentation/testing/migratingfromxctest), [asynchronous tests](https://developer.apple.com/documentation/testing/testing-asynchronous-code), [test repetition proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0024-per-test-case-repetitions.md).
