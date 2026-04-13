# Async Testing and Concurrency

## Async Test Functions

Mark the test function `async` — do NOT wrap async code in `Task { }`.

```swift
// WRONG — Task fires and forgets; test passes before Task completes
@Test func fetchData() {
    Task {
        let result = await api.fetch()
        #expect(result.count > 0)  // NEVER REPORTED
    }
}
// Test passes in 0.001 seconds even though fetch takes 2 seconds

// CORRECT — mark function async
@Test func fetchData() async {
    let result = await api.fetch()
    #expect(result.count > 0)  // properly reported
}
// Test takes 2+ seconds, failures are caught
```

**Why Task { } is dangerous:** `Task.init` creates an unstructured task whose lifetime is not tied to the test function. The test function returns immediately, Swift Testing marks the test as passed, and any `#expect` failures recorded after the test has already completed are silently lost. (Note: `Task.init` inherits the caller's actor context — the problem is unstructured lifetime, not an executor hop.)

## await Inside #expect

Place `await` inside the macro parentheses:

```swift
// CORRECT
#expect(await asyncCall() == "expected")

// ALSO CORRECT — extract to variable
let result = await asyncCall()
#expect(result == "expected")

// WRONG — await before the macro
await #expect(asyncCall() == "expected")
```

## confirmation() — Deep Dive

Replaces `XCTestExpectation` + `waitForExpectations`. Fundamentally different pattern.

### XCTest pattern (DON'T use this)

```swift
// XCTest — create, do work, wait
let exp = expectation(description: "callback")
sut.onComplete { exp.fulfill() }
sut.start()
waitForExpectations(timeout: 5)
```

### Swift Testing pattern

```swift
// Swift Testing — block-scoped
await confirmation { confirm in
    sut.onComplete { confirm() }
    sut.start()
}
// confirm() must be called before the closure returns.
// If it isn't, an issue is recorded. Use `try await` only when the closure body throws.
```

### Expected count

```swift
// Expect exactly 3 confirmations
await confirmation(expectedCount: 3) { confirm in
    sut.onEachItem { _ in confirm() }
    sut.processItems([a, b, c])
}

// Expect at least 1 but no more than 5
await confirmation(expectedCount: 1...5) { confirm in
    sut.onEvent { confirm() }
}

// Expect zero calls (callback should NOT fire)
await confirmation(expectedCount: 0) { confirm in
    sut.onError { confirm() }  // should not be called
    sut.processValidData()
}
```

### Named confirmations

```swift
await confirmation("delegate notified") { confirm in
    sut.delegate = MockDelegate(onUpdate: { confirm() })
    sut.refresh()
}
```

## Bridging Closure-Based Async

For legacy callback-based APIs that aren't `async`, use `withCheckedContinuation`:

```swift
@MainActor
@Test func closureBasedAPI() async {
    let result = await withCheckedContinuation { continuation in
        closureTimesTwo(5.8, completion: { double in
            continuation.resume(returning: double)
        })
    }
    #expect(result == 11.6)
}
```

## Parallel Execution (Default)

Tests run in **parallel by default**, in random order. Each test runs in its own Swift Task.

```swift
@Suite struct AsyncTests {
    @Test func fetchA() async { ... }  // runs in parallel
    @Test func fetchB() async { ... }  // runs in parallel
}
// Both start simultaneously. Suite time ≈ max(fetchA, fetchB), not sum.
```

This is a feature: parallel tests find hidden shared-state dependencies.

## Serialized Execution

Use `.serialized` only when tests genuinely depend on shared mutable state.

```swift
@Suite(.serialized)
struct OrderedTests {
    let state = SharedState.instance

    @Test("Step 1: Setup")
    func setup() { state.configure() }

    @Test("Step 2: Execute")
    func execute() { state.run() }  // runs AFTER setup

    @Test("Step 3: Verify")
    func verify() { #expect(state.result == expected) }  // runs AFTER execute
}
```

**Ordering:** Apple docs guarantee serial execution. In practice, tests run top to bottom by source line number, though this ordering behavior is observed, not formally documented.

### Scope of .serialized

`.serialized` guarantees order **only within the suite** it's applied to.

```swift
// PROBLEM: These two suites share CurrentValue.shared but run in PARALLEL
@Suite(.serialized) struct NumberEntry {
    let current = CurrentValue.shared
    @Test func recordTwo() { current.record(digit: "2") }
    @Test func recordThree() { current.record(digit: "3") }
}

@Suite(.serialized) struct DecimalPoint {
    let current = CurrentValue.shared
    @Test func record23() { current.displayedValue = "23" }
    @Test func addPoint() { current.decimalPoint() }
}
// NumberEntry and DecimalPoint run their internal tests in order,
// but the two suites run in PARALLEL — causing cross-contamination

// SOLUTION: Nest under a parent serialized suite
@Suite(.serialized)
struct DisplayEntry {
    @Suite(.tags(.numberEntry))
    struct NumberEntry { ... }  // serialized internally

    @Suite(.tags(.decimalPoint))
    struct DecimalPoint { ... }  // serialized internally; parent ensures mutual exclusion
}
```

### Cross-contamination pattern

When multiple serialized suites share a static/singleton resource:

```swift
// Each suite should clear shared state in its first test
@Suite(.serialized)
struct NumberEntry {
    let current = CurrentValue.shared

    @Test("Display is initially empty")
    func emptyDisplay() {
        current.clear()  // IMPORTANT: reset shared state
        #expect(current.displayedValue.isEmpty == true)
    }
    // ... subsequent tests
}
```

## @MainActor Test Suites

When testing `@MainActor`-isolated types, annotate the suite:

```swift
@MainActor
@Suite("ViewModel Tests")
struct ViewModelTests {
    let sut = MyViewModel()  // @MainActor type

    @Test func initialState() {
        #expect(sut.isLoading == false)
    }

    @Test func loadData() async {
        await sut.load()
        #expect(sut.items.count > 0)
    }
}
```

Without `@MainActor` on the suite, accessing MainActor-isolated properties will cause compiler errors. **Exception:** If the module uses default actor isolation (`-default-isolation MainActor`, SE-0466), the suite is already implicitly MainActor-isolated and the annotation is unnecessary.

## Time Limits

```swift
@Test(.timeLimit(.minutes(1)))
func networkOperation() async {
    let data = await fetchLargeDataset()
    #expect(data.count > 0)
}
// If test exceeds 1 minute, it's cancelled and records "Time limit was exceeded"
```

Time limits apply **per test case** in parameterized tests — each argument combination gets its own timeout.

## init() Can Be Async

Unlike XCTest's `setUp()`, Swift Testing suite initializers can be `async throws`:

```swift
@Suite struct IntegrationTests {
    let testDB: Database

    init() async throws {
        testDB = try await Database.createTestInstance()
    }

    @Test func query() async throws {
        let results = try await testDB.query("SELECT 1")
        #expect(!results.isEmpty)
    }
}
```
