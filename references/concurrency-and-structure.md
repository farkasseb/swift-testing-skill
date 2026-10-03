# Suites, Concurrency, and Parameterized Tests

## Suites and lifecycle

- Any type containing `@Test` methods is a suite; `@Suite` adds a display name and traits. Built-in suite traits (tags, `.serialized`, `.timeLimit`, enable/disable conditions, issue handling) reach every contained test. A custom suite trait reaches them only when its `isRecursive` is `true`.
- Each test case, including each parameterized argument case, gets a fresh instance. `init()` is the setup and can be `async throws`. Prefer a `struct`.
- Teardown goes in `deinit`, which needs a `final class` or an `actor` suite. `deinit` cannot be `async` or `throws`; for that, use a `TestScoping` trait ([modern-apis.md](modern-apis.md#custom-and-scoping-traits)).
- A test that mutates a stored property of a struct suite must be `mutating`:

```swift
struct CartTests {
    var cart = Cart()

    @Test mutating func `Adding an item increases the count`() {
        cart.add("apple")
        #expect(cart.count == 1)
    }
}
```

An escaping closure cannot capture a `mutating self`. Move that state into a local `var` in the test instead.

## Parallelism and `.serialized`

Tests run in parallel on arbitrary tasks, in no guaranteed order. XCTest ran synchronous tests on the main actor, one at a time. Hidden dependencies on either behavior surface as flakiness after a migration.

`.serialized` (on a suite, or on a parameterized test to serialize its cases) stops tests from overlapping within that scope only:

```swift
@Suite(.serialized) struct DisplayTests {       // one shared-state group
    @Suite struct NumberEntry { /* tests */ }
    @Suite struct DecimalPoint { /* tests */ }
}
```

Two sibling `@Suite(.serialized)` types would still run in parallel with each other. Serialization never covers other suites that touch the same static or singleton, so resetting it in each suite is insufficient while another suite can still use it. Group every user under one serialized parent or give each test an independent resource. Serialization prevents overlap, not a particular declaration order.

## Main actor

Annotate a suite or test `@MainActor` when it touches main-actor-isolated API. During a migration, add it only where the XCTest version relied on main-thread execution. Default main-actor isolation (SE-0466) can infer it for unannotated suite types; check the test target's effective settings. `@MainActor` protects synchronous actor access, but async tests can interleave at `await`. It is not a substitute for `.serialized` when a shared invariant must hold for the whole test.

## Confirmation

`confirmation` checks how many times `confirm()` ran by the time its closure returns. It does not wait for later calls.

```swift
await confirmation("item processed", expectedCount: 3) { confirm in
    processor.onItem = { _ in confirm() }
    await processor.process(["a", "b", "c"])
}

await confirmation(expectedCount: 1...) { confirm in       // Swift 6.1: ranges
    emitter.onEvent = { confirm() }
    await emitter.run()
}
```

`expectedCount: 0` asserts that a callback did not fire, but only for calls that happen before the closure returns. For callbacks that fire later, await the value instead ([migration.md](migration.md#completion-handlers)).

## Time limits

`.timeLimit(.minutes(1))` records a failure and requests cancellation when a test runs too long. Cancellation is cooperative: a continuation that never resumes or other non-cooperative work can keep the process running. It is not a precise wall-clock watchdog. It applies per test case in parameterized tests. Minutes are the only unit. The effective limit is the shortest of those set on the test and its suites.

## Enabling and skipping

```swift
@Test(.disabled("Waiting on FB12345"))             func a() { }
@Test(.enabled(if: FeatureFlags.newParser))       func b() { }
@available(macOS 26, iOS 26, *) @Test             func c() { }   // OS gate: prefer @available
@Test(.bug("https://example.com/issues/42"))     func d() { }   // metadata only; still runs
```

A test marked `@available` for a newer OS is skipped on older systems. Use `try Test.cancel(_:)` for conditions only known while the test runs.

## Tags

```swift
extension Tag {
    @Tag static var networking: Self
}

@Suite(.tags(.networking)) struct APITests { /* ... */ }
```

Tags group tests across suites. `swift test` cannot filter by tag before Swift 6.5 (ST-0025); `--filter` matches names only.

`.tags("slow")` does not compile: tags must be declared `@Tag` static members, as above.

## Parameterized tests

```swift
struct PricingTests {
    static let prices: [Decimal] = [0, 9.99, 100]
    static let regions = [Region.us, .eu]

    @Test(arguments: prices)
    func nonNegative(price: Decimal) { #expect(price >= 0) }

    @Test(arguments: regions, prices)                   // Cartesian product: 6 cases
    func taxIsApplied(region: Region, price: Decimal) { /* ... */ }

    @Test(arguments: zip([1, 2, 3], [2, 4, 6]))          // paired: 3 cases
    func doubles(input: Int, expected: Int) { #expect(input * 2 == expected) }
}
```

- Keep a loop when its iterations exercise repeated calls or state transitions on the same SUT. Parameterization creates independent cases and loses that sequence.
- At most two argument collections. For a third dimension, zip two of them, and wrap the zip in `Array(...)` when it is one of two arguments.
- Arguments must be `Sendable`. They are evaluated before any instance exists, so use `static` members or literals.
- Conform an argument type to `CustomTestStringConvertible` to control its name in results. Tuples cannot conform; use a small wrapper struct.
- Xcode can rerun a single case when the argument is `Encodable`, `RawRepresentable`, `Identifiable`, or `CustomTestArgumentEncodable`.

Sources: [parallelization](https://developer.apple.com/documentation/testing/parallelization), [confirmation](https://developer.apple.com/documentation/testing/confirmation), [trait scope defaults](https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Traits/Trait.swift).
