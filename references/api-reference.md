# Swift Testing API Reference

## @Test Attribute

Marks a function as a test. No naming convention required (no `test` prefix).

```swift
// Basic
@Test func myTest() { ... }

// With display name
@Test("User can complete checkout") func checkout() { ... }

// With traits
@Test(.tags(.networking), .timeLimit(.minutes(1)))
func fetchData() async { ... }

// Async and throwing
@Test func riskyAsync() async throws { ... }
```

**Rules:**
- Can be applied to instance methods, static methods, or free functions
- Functions must have zero parameters (unless using `arguments:` for parameterized tests)
- Can use `async`, `throws`, `@MainActor`
- No `test` prefix required — use descriptive names

## @Suite Attribute

Groups test functions. Not required — any type containing `@Test` functions is implicitly a suite.

```swift
// Explicit suite with display name
@Suite("Authentication Tests")
struct AuthTests { ... }

// With traits (inherited by all tests)
@Suite(.serialized, .tags(.auth))
struct AuthTests { ... }

// Nested suites
@Suite("Outer")
struct Outer {
    @Suite("Inner")
    struct Inner {
        @Test func nested() { ... }
    }
}
```

**Rules:**
- Prefer `struct` over `class` — each test gets a fresh instance
- Types must have zero-argument `init()` if containing instance methods
- `@Suite` is optional for recognition but enables display name and traits
- Traits on a suite are inherited by all contained tests and nested suites

## #expect Macro

Records an issue if condition is false. Test **continues** after failure.

```swift
// Boolean
#expect(value == 42)
#expect(array.isEmpty)
#expect(flag == true)

// With try (inside, not outside)
#expect(try riskyCall() == 42)

// With await (inside, not outside)
#expect(await asyncCall() == "done")

// Both
#expect(try await fetchValue() > 0)

// Optional check
#expect(optionalValue != nil)

// IMPORTANT: try/await go INSIDE the parentheses
// WRONG: try #expect(foo() == 42)
// CORRECT: #expect(try foo() == 42)

// IMPORTANT: try only on LEFT side of ==
// WRONG: #expect(try foo() == try bar())
// CORRECT:
let expected = try bar()
#expect(try foo() == expected)
```

## #require Macro

Same as `#expect` but **throws** on failure, stopping the test. Always needs `try`.

```swift
// Boolean — stops test on failure
try #require(condition)

// Optional unwrapping — returns non-optional value
let value = try #require(optionalValue)
// value is now non-optional; test stops if nil

// With await
let data = try #require(await fetchOptional())
```

**Key difference from #expect:** Use `#require` when the test cannot meaningfully continue if the check fails (e.g., unwrapping a value needed for subsequent assertions).

## Error Testing

### Check that specific error type is thrown

```swift
#expect(throws: MyError.self) {
    try riskyOperation()
}
```

### Check that specific error value is thrown

```swift
#expect(throws: CalculationError.divideByZero) {
    try divide(6, by: 0)
}
```

### Check that NO error is thrown

```swift
#expect(throws: Never.self) {
    try safeOperation()
}
```

### Inspect the thrown error (ST-0006)

`#expect(throws:)` and `#require(throws:)` **return the thrown error** for further inspection. The old error matcher closure is deprecated.

```swift
// #require returns non-optional — stops test if wrong error
let error = try #require(throws: MyError.self) {
    try riskyOperation()
}
#expect(error == .invalidInput)
#expect(error.details.contains("missing field"))

// #expect returns optional (nil if expectation failed)
let error = #expect(throws: NetworkError.self) {
    try fetchData()
}
#expect(error?.statusCode == 404)
```

**Prefer this over the deprecated matcher closure pattern.** No more casting from `any Error`.

## Exit Testing

Tests code that causes process termination (preconditions, fatalError).

```swift
// Check for successful exit
await #expect(processExitsWith: .success) {
    exit(0)
}

// Check for failure exit
await #expect(processExitsWith: .failure) {
    preconditionFailure("boom")
}

// Check specific exit code
await #expect(processExitsWith: .exitCode(42)) {
    exit(42)
}

// Observe stdout/stderr (key paths into ExitTest.Result)
let result = await #expect(processExitsWith: .failure, observing: [\.standardOutputContent]) {
    print("output before crash")
    fatalError()
}
if let result {
    #expect(result.standardOutputContent.contains(UInt8(ascii: "o")))
}
```

### Capturing values in exit tests (Swift 6.3)

Exit tests can capture values from the enclosing scope via closure capture lists. Captured values must conform to `Sendable & Codable`.

```swift
@Test(arguments: [Fruit.olive, .tomato])
func feedFruitBat(_ fruit: Fruit) async {
    await #expect(processExitsWith: .failure) { [fruit] in
        fruit.feed(to: FruitBat())  // precondition failure expected
    }
}
```

Without the capture list, exit tests cannot reference non-constant values from the enclosing context.

**Note:** Spawns a child process. Available on macOS, Linux, and Windows only — **not available on iOS/watchOS/tvOS/visionOS** (no process spawning support).

## withKnownIssue

Marks expected failures. When the bug is **fixed**, the test **fails** — alerting you to remove the wrapper.

```swift
// Basic
@Test func brokenFeature() {
    withKnownIssue {
        #expect(broken() == expected)
    }
}

// Async version
@Test func brokenAsync() async {
    await withKnownIssue {
        let result = await brokenAPI()
        #expect(result == expected)
    }
}

// Intermittent — failure may or may not happen
withKnownIssue(isIntermittent: true) {
    #expect(flakyOperation() == expected)
}

// Conditional — only treat as known issue when condition is true
withKnownIssue {
    #expect(result == expected)
} when: {
    isRunningOnCI
}

// Matching specific issues
withKnownIssue {
    #expect(result == expected)
} matching: { issue in
    issue.description.contains("timeout")
}
```

**Key behavior:** If no failure occurs inside `withKnownIssue`, the test records "Known issue was not recorded" — this signals the underlying bug is fixed.

## confirmation()

Replaces `XCTestExpectation` + `waitForExpectations`. Block-scoped pattern.

```swift
// Basic — expect exactly 1 confirmation
await confirmation { confirm in
    sut.onComplete { confirm() }
    sut.start()
}

// Use `try await` only when the closure body throws
try await confirmation { confirm in
    try sut.riskyStart { confirm() }
}

// Multiple confirmations expected
await confirmation(expectedCount: 3) { confirm in
    sut.onEachItem { _ in confirm() }
    sut.processItems([a, b, c])
}

// Range-based count
await confirmation(expectedCount: 1...5) { confirm in
    sut.onEvent { confirm() }
}

// Named for clarity
await confirmation("delegate callback received") { confirm in
    sut.delegate = CallbackDelegate { confirm() }
    sut.trigger()
}
```

**Critical pattern:** `confirmation()` is **block-scoped** — the confirmation closure must be called within the trailing closure. This is fundamentally different from XCTestExpectation's create-then-fulfill pattern.

## Issue.record

Replacement for `XCTFail()`.

```swift
@Test func validate() {
    guard condition else {
        Issue.record("Condition was not met")
        return
    }
}
```

## Issue Severity (Swift 6.3)

Record non-failing warnings that appear in test results but don't cause test failure:

```swift
// Warning — test still passes
Issue.record("Image match 93% — above 90% threshold but not identical", severity: .warning)

// Error (default) — test fails
Issue.record("Missing required configuration")  // severity: .error is the default
```

`Issue.Severity` has two cases: `.warning` and `.error`. Use `issue.isFailure` to check if an issue causes test failure (accounts for both severity and `withKnownIssue`).

## Test.cancel() (Swift 6.3)

Cancel a running test. Unlike `.disabled()` which prevents a test from starting, `Test.cancel()` stops a test **after** it has begun — useful for runtime-dependent conditions.

```swift
@Test func serverTest() throws {
    guard server.isReachable else {
        try Test.cancel("Server unreachable")
    }
    // ... test body
}
```

For **parameterized tests**, cancels only the current test case — other cases continue:

```swift
@Test(arguments: allSpecies)
func checkExtinction(_ species: Species) throws {
    if species.isExtinct {
        try Test.cancel("\(species) is extinct, skipping")
    }
    // ... only non-extinct species reach here
}
```

`Test.cancel()` throws to simplify control flow — no `return` needed after the call.

## CustomTestStringConvertible

Controls how values appear in the Test Navigator for parameterized tests. See [parameterized-testing.md](parameterized-testing.md) for full details, wrapper types, and `@retroactive` conformance patterns.

## Attachment

Attach data to test results for debugging.

```swift
@Test func generateReport() {
    let data = generateData()
    Attachment.record(data, named: "report.json")
    #expect(data.isValid)
}
```

Types can conform to `Attachable` for custom serialization.
