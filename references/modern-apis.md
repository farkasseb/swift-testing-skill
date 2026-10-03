# Newer Swift Testing APIs

Version gates are toolchain versions unless an OS floor is stated.

## Errors

`#expect(throws:)` returns the thrown error as an optional; `#require(throws:)` returns it non-optional and stops the test on mismatch (Swift 6.1, ST-0006). The older `throws:` matcher-closure overloads are soft-deprecated.

```swift
#expect(throws: ParseError.badHeader) { try parse(data) }   // exact Equatable value
#expect(throws: Never.self) { try parse(valid) }            // must not throw

let error = #expect(throws: ParseError.self) { try parse(data) }
#expect(error?.line == 3)                                   // test continues on mismatch

let fatal = try #require(throws: ParseError.self) { try parse(data) }
#expect(fatal.line == 3)                                    // test stopped on mismatch
```

Pick `#expect` when the surrounding assertions should still run, `#require` when they cannot.

## Exit tests

`#expect(processExitsWith:)` runs the closure in a child process and checks how it ends (Swift 6.2, ST-0008). Available on macOS, Linux, FreeBSD, OpenBSD, and Windows; unavailable on iOS, tvOS, watchOS, and visionOS. Always `await` it.

```swift
@Test func rejectsNegativeCount() async {
    await #expect(processExitsWith: .failure) {
        _ = Inventory(count: -1)   // precondition failure
    }
}

@Test(arguments: [-1, -5])
func rejects(count: Int) async {
    // Swift 6.3 (ST-0012): capture values; they must be Sendable & Codable.
    await #expect(processExitsWith: .failure) { [count] in
        _ = Inventory(count: count)
    }
}
```

Conditions: `.success`, `.failure`, `.exitCode(_:)`, `.signal(_:)`. Pass `observing: [\.standardErrorContent]` to get the output back in the returned `ExitTest.Result?`.

## Attachments

`Attachment.record(value, named:)` attaches data to the test result (Swift 6.2, ST-0009). `String`, `Data`, and `[UInt8]` work directly. A `Codable` or `NSSecureCoding` type gets the encoding implementation but must still declare `Attachable`. Explicitly `import Foundation` in the file to activate the overlay; XCTest re-exporting Foundation was insufficient in the iOS probe:

```swift
import Foundation
import Testing

struct Snapshot: Codable, Attachable { var rows: [String] }

@Test func export() {
    Attachment.record(Snapshot(rows: ["a"]), named: "snapshot.json")
}
```

Images (Swift 6.3, ST-0014/ST-0017): `UIImage`, `NSImage`, `CGImage`, and `CIImage` conform to `AttachableAsImage` and attach directly. The format is optional.

```swift
Attachment.record(image, named: "rendered", as: .png)
Attachment.record(image, named: "rendered", as: .jpeg(withEncodingQuality: 0.8))
```

`Transferable` values (Swift 6.4, ST-0023) use an async throwing initializer, and the OS floor is iOS 18.2 / macOS 15.2 because it comes from CoreTransferable. On older targets, export to `Data` yourself and attach that.

```swift
let attachment = try await Attachment(exporting: document, as: .pdf, named: "report.pdf")
Attachment.record(attachment)
```

There is no trait that keeps attachments only for failing tests. Record conditionally instead:

```swift
if !matches(rendered, reference) {
    Attachment.record(rendered, named: "rendered", as: .png)
    Issue.record("Rendered image differs from the reference")
}
```

Xcode stores recorded attachments in the test results (`.xcresult`). `swift test` writes them to disk only when given `--attachments-path <existing directory>`.

## Issues, severity, and cancellation

```swift
Issue.record("Unexpected state")                                   // fails the test
Issue.record("Match was 93%, threshold 90%", severity: .warning)   // Swift 6.3: reported, does not fail
```

`Issue.Severity` is `.warning` or `.error` (default). `issue.isFailure` tells whether an issue fails the test.

`try Test.cancel("reason")` (Swift 6.3, ST-0016) ends a test that has already started without failing it, the runtime counterpart of `.disabled(if:)` / `.enabled(if:)`. In a parameterized test it cancels only the current case. It returns `Never`, so it works as a `guard` exit:

```swift
@Test func syncsWithServer() async throws {
    guard await server.isReachable else {
        try Test.cancel("Server unreachable")
    }
    // ...
}
```

## Custom and scoping traits

A trait conforming to `TestScoping` wraps the tests it applies to (Swift 6.1, ST-0007). Use it for a reusable setup/teardown recipe across suites, or teardown that must be `async` or `throws` (a `deinit` cannot be). The test reads what the trait provides through a `@TaskLocal`:

```swift
enum TestDatabase {
    @TaskLocal static var current: Database?
}

struct TemporaryDatabaseTrait: TestTrait, SuiteTrait, TestScoping {
    // On a suite: wrap each test case, not the whole suite once.
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let database = try await Database.makeTemporary()
        do {
            try await TestDatabase.$current.withValue(database) {
                try await function()
            }
        } catch {
            // Tear down on failure too, without hiding the original error.
            do { try await database.destroy() } catch { Issue.record(error) }
            throw error
        }
        try await database.destroy()
    }
}

extension Trait where Self == TemporaryDatabaseTrait {
    static var temporaryDatabase: Self { Self() }
}

@Test(.temporaryDatabase) func insertsRow() async throws {
    let database = try #require(TestDatabase.current)
    try await database.insert("row")
}
```

`SuiteTrait.isRecursive` defaults to `false`. A non-recursive scoping trait on a suite runs its scope once around the whole suite, so every test would share one database. A recursive one propagates to every contained test, including nested suites, and wraps each test case separately (each argument of a parameterized test gets its own scope); it must also conform to `TestTrait`, or the runner traps while building the test plan. Traits without `TestScoping` can still act through `prepare(for:)` or by returning a separate scope provider from `scopeProvider(for:testCase:)`.

## Issue-handling traits

Swift 6.2 (ST-0011). They transform or drop issues recorded by the test before they are reported:

```swift
@Test(.compactMapIssues { issue in
    var issue = issue
    issue.comments.append("Device: \(deviceName)")
    return issue
})
func rendersOnDevice() { /* ... */ }

@Test(.filterIssues { issue in issue.severity == .error })
func ignoresWarnings() { /* ... */ }
```

Returning `nil` from `compactMapIssues`, or `false` from `filterIssues`, suppresses the issue. Do not use them to hide regressions. Use `withKnownIssue` for an intentionally tracked known bug; it fails if no matching issue occurs, unless `isIntermittent: true`.

## CustomTestReflectable

Swift 6.4 (ST-0022). Controls the value breakdown shown when an `#expect` fails, without changing `CustomReflectable` for production code:

```swift
extension Invoice: CustomTestReflectable {
    var customTestMirror: Mirror {
        Mirror(self, children: ["id": id, "total": total])
    }
}
```

Since 6.4 the expanded failure breakdown also appears in `swift test` console output.

## Repetition

There is no repetition trait. Xcode has long offered repetition in test plans and scheme test options. Swift 6.4 (ST-0024) adds it to `swift test` and reruns only the test cases that met the condition, where earlier releases reran the whole target:

```bash
swift test --filter FlakyTests --repeat-until fail --maximum-repetitions 100   # catch a flaky failure
swift test --repeat-until pass --maximum-repetitions 3                         # retry
```

On Xcode 27.1 beta, a case that failed twice then passed on the third repetition produced a final passing test summary but `swift test` still exited 1. Read both the case outcomes and process status; do not assume retry-until-pass makes CI green.

## Unavailable in the audited libraries

- No `.repeating` trait or `Test.currentIteration`; use the runner options above.
- No `.timeLimit(.seconds(...))`; use a bounded operation adapter for shorter deadlines.
- No failure-only attachment trait. ST-0018 remains returned for revision; record conditionally.
- No `accuracy:` parameter on `#expect`.
- Tag filtering (ST-0025), the task-local trait (ST-0026), source-location macro (ST-0027), and revised Encodable attachments (ST-0028) are marked implemented for Swift 6.5, outside the installed Swift 6.3/6.4 libraries. Proposal acceptance does not establish installed availability.

Sources: [Swift Testing proposals](https://github.com/swiftlang/swift-evolution/tree/main/proposals/testing), [TestScoping](https://developer.apple.com/documentation/testing/testscoping), and the selected Xcode's `Testing.swiftinterface` and `_Testing_CoreTransferable.swiftinterface`.
