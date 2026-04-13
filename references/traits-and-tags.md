# Traits and Tags

## Built-in Traits

### .serialized

Runs tests serially (one at a time) within the suite.

```swift
@Suite(.serialized)
struct OrderedTests {
    let state = SharedState.instance
    @Test func step1() { state.setup() }
    @Test func step2() { state.verify() }  // runs after step1
}
```

**Ordering:** Apple docs guarantee serial (non-parallel) execution within a suite. In practice, tests execute in source-file order (by line number), though this specific ordering is observed behavior, not a documented guarantee.

**Scope rules:**
- `.serialized` guarantees order only **within that suite**
- Sibling serialized suites run **in parallel with each other**
- To prevent cross-suite parallelism, nest under a parent serialized suite:

```swift
@Suite(.serialized)
struct AllEntryTests {
    @Suite struct NumberEntry { ... }    // runs all tests in order
    @Suite struct DecimalPoint { ... }   // waits for NumberEntry to finish
}
```

**When to use:** Only when tests genuinely depend on shared mutable state and execution order. Default parallel execution is preferred — it catches hidden dependencies.

### .timeLimit

Sets a timeout. Test fails if exceeded. Cancels the test's task.

```swift
@Test(.timeLimit(.minutes(1)))
func networkCall() async { ... }

@Test(.timeLimit(.minutes(5)))
func longOperation() async { ... }
```

Only `.minutes(_:)` is available — `TimeLimitTrait.Duration` enforces minute-based granularity (minimum 1 minute) to prevent flaky tests from overly-short timeouts. Applied per test case in parameterized tests (each case gets its own time limit).

### .disabled

Skips the test with a reason. Replaces `XCTSkip`.

```swift
@Test(.disabled("Server is down for maintenance"))
func serverTest() async { ... }

// Conditional disable
@Test(.disabled(if: !ProcessInfo.processInfo.environment.keys.contains("API_KEY"),
                "API_KEY environment variable required"))
func apiTest() { ... }
```

### .enabled

Conditional execution — runs only when condition is true.

```swift
@Test(.enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 18))
func newOSFeature() { ... }
```

### .bug

Associates a bug tracker reference. Does **NOT** skip or disable the test.

```swift
@Test(.bug("https://jira.example.com/PROJ-123", "Flaky on CI"))
func sometimesFlaky() { ... }

// With ID only
@Test(.bug(id: "PROJ-456"))
func related() { ... }
```

### .tags

Semantic categorization for filtering test execution. See Tags section below.

```swift
@Test(.tags(.networking, .slow))
func heavyNetworkTest() async { ... }
```

### Combining traits

```swift
@Test(.timeLimit(.minutes(1)),
      .bug("https://jira.example.com/PROJ-789", "Performance regression"),
      .tags(.networking),
      .disabled("Blocked by PROJ-790"))
func complexTest() async { ... }
```

### Trait inheritance

Traits applied to a `@Suite` are inherited by all contained tests and nested suites:

```swift
@Suite(.tags(.networking), .serialized)
struct NetworkTests {
    // Both tests inherit .tags(.networking) and .serialized
    @Test func fetch() { ... }
    @Test func upload() { ... }
}
```

## Tags

Tags provide semantic categorization orthogonal to suite structure. Use for cross-cutting concerns.

### Declaring tags

Tags MUST be declared as static members on `Tag`. String literals do NOT work.

```swift
// CORRECT — declare via extension
extension Tag {
    @Tag static var networking: Self
    @Tag static var slow: Self
    @Tag static var authentication: Self
    @Tag static var display: Self
}

// WRONG — string-based tags don't compile
@Test(.tags("networking")) func fetch() { ... }  // ERROR
```

### Using tags

```swift
@Test(.tags(.networking))
func fetchData() async { ... }

// Multiple tags
@Test(.tags(.networking, .slow))
func heavyFetch() async { ... }

// On suites (inherited by all tests)
@Suite(.tags(.authentication))
struct AuthTests { ... }
```

### Running by tag

In Xcode: Tests Navigator → filter by tag.

## Comments as Documentation

Swift comments immediately before `@Test` or `@Suite` are captured and displayed in test results:

```swift
// This test verifies the login flow with valid credentials
@Test func loginWithValidCredentials() { ... }

/// Checks that expired tokens are properly refreshed
@Test func tokenRefresh() async { ... }
```

## Custom Traits

### TestTrait / SuiteTrait

Create custom traits by conforming to `TestTrait` (for test functions) or `SuiteTrait` (for suites):

```swift
struct DatabaseTrait: TestTrait, SuiteTrait {
    let databaseName: String
}

extension Trait where Self == DatabaseTrait {
    static func database(_ name: String) -> Self {
        DatabaseTrait(databaseName: name)
    }
}

// Usage
@Test(.database("testDB"))
func queryTest() { ... }
```

### TestScoping — Setup/Teardown Replacement

For shared setup/teardown logic, implement `TestScoping`:

```swift
struct DatabaseTrait: TestTrait, TestScoping {
    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        // Setup
        let db = try await Database.create()
        defer { db.destroy() }

        // Run the test
        try await function()

        // Teardown happens in defer
    }
}
```

This replaces XCTest's `setUp()`/`tearDown()` for shared setup logic. For simple per-test setup, use `init()` on the suite struct instead.

### Issue Handling Traits (Swift 6.2)

Filter or transform issues recorded during tests using `IssueHandlingTrait`:

```swift
// Suppress known flaky timeout issues
@Test(.filterIssues { !$0.description.contains("timeout") })
func networkTest() async { ... }

// Return nil from compactMapIssues to suppress, or modify and return
@Test(.compactMapIssues { issue in
    issue.description.contains("expected") ? nil : issue
})
func selectiveTest() { ... }
```
