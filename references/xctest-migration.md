# XCTest to Swift Testing Migration

## Quick Reference Table

| XCTest | Swift Testing | Notes |
|--------|--------------|-------|
| `import XCTest` | `import Testing` | Different framework |
| `class FooTests: XCTestCase` | `@Suite struct FooTests` | Prefer struct; no inheritance |
| `func testXxx()` | `@Test func xxx()` | No `test` prefix needed |
| `setUp()` | `init()` | Can be `async throws` |
| `tearDown()` | `deinit` | Only on class suites |
| `setUpWithError() throws` | `init() throws` | |
| `XCTAssert(x)` | `#expect(x)` | |
| `XCTAssertTrue(x)` | `#expect(x)` or `#expect(x == true)` | |
| `XCTAssertFalse(x)` | `#expect(!x)` or `#expect(x == false)` | |
| `XCTAssertEqual(a, b)` | `#expect(a == b)` | |
| `XCTAssertNotEqual(a, b)` | `#expect(a != b)` | |
| `XCTAssertGreaterThan(a, b)` | `#expect(a > b)` | |
| `XCTAssertLessThan(a, b)` | `#expect(a < b)` | |
| `XCTAssertGreaterThanOrEqual(a, b)` | `#expect(a >= b)` | |
| `XCTAssertLessThanOrEqual(a, b)` | `#expect(a <= b)` | |
| `XCTAssertNil(x)` | `#expect(x == nil)` | |
| `XCTAssertNotNil(x)` | `#expect(x != nil)` | |
| `XCTUnwrap(x)` | `try #require(x)` | Returns unwrapped value |
| `XCTAssertThrowsError` | `#expect(throws: Type.self) { }` | Returns the error for inspection (ST-0006, Swift 6.1+) |
| `XCTAssertNoThrow` | `#expect(throws: Never.self) { }` | |
| `XCTExpectFailure` | `withKnownIssue { }` | Fails when issue is fixed |
| `XCTSkip` / `XCTSkipIf` | `.disabled()` / `.enabled(if:)` (pre-start) or `try Test.cancel()` (runtime, Swift 6.3) | |
| `XCTestExpectation` | `confirmation()` | Block-scoped |
| `waitForExpectations(timeout:)` | (built into confirmation) | |
| `XCTFail("msg")` | `Issue.record("msg")` | Or promote to `#expect`/`try #require` where the guard shape allows |
| `XCTAttachment` + `add(_:)` | `Attachment.record(value, named:)` | Images directly since Swift 6.3 (`as: .png`) |
| `addTeardownBlock { }` | `deinit` or custom `TestScoping` trait | |
| `measure { }` | Not available | Use XCTest for perf tests |

**Test naming:** drop the `test` prefix. For multi-word names that read like a sentence, prefer a raw identifier (SE-0451, **Swift 6.2+** — use `@Test("display name")` on older toolchains) — Apple's own migration guidance uses this style: `func testEngineDoesNotStall()` → ``@Test func `Engine does not stall`()``.

**`continueAfterFailure = false`:** every subsequent assertion in the affected scope must become `try #require(...)`, not `#expect(...)` — `#expect` continues on failure, which silently changes test semantics. If it was set in `setUp`, this applies to all assertions in all migrated test methods of that class.

## Key Differences

### Suite types: struct vs class

```swift
// XCTest — must be class
class MyTests: XCTestCase { ... }

// Swift Testing — prefer struct
@Suite struct MyTests { ... }

// Each @Test function gets a FRESH struct instance
// Properties don't carry between tests
```

### Test lifecycle

```swift
// XCTest
class Tests: XCTestCase {
    var sut: MyType!
    override func setUp() { sut = MyType() }
    override func tearDown() { sut = nil }
    func testSomething() { XCTAssertNotNil(sut) }
}

// Swift Testing
@Suite struct Tests {
    let sut: MyType
    init() { sut = MyType() }  // runs before EACH test
    @Test func something() { #expect(sut != nil) }
}
```

**init() can be async:** Unlike XCTest's `setUp()`, Swift Testing's `init()` can be `async throws`:
```swift
@Suite struct AsyncSetupTests {
    let data: Data
    init() async throws {
        data = try await loadTestFixture()
    }
}
```

### Accessing internal types

Test targets can't see `internal` types by default. Use `@testable import` to expose them:

```swift
@testable import MyApp
import Testing

@Suite struct ParserTests {
    @Test func parsesMarkdown() {
        let parser = MarkdownParser(markdown: "**bold**")  // internal type
        #expect(parser.text == "<p><strong>bold</strong></p>")
    }
}
```

`@testable import` only works when the module is built with testing enabled (default in Xcode test targets). It does not expose `private` or `fileprivate` members.

### Assertion power: #expect shows both sides

XCTest: `XCTAssertEqual(a, b)` → "XCTAssertEqual failed: 42 is not equal to 43"
Swift Testing: `#expect(a == b)` → "Expectation failed: (a → 42) == (b → 43)"

The macro captures the full expression and shows each value, making failures far more informative.

### No naming convention

```swift
// XCTest — MUST start with "test"
func testUserCanLogin() { ... }

// Swift Testing — any name works, use display name for readability
@Test("User can log in with valid credentials")
func loginWithValidCredentials() { ... }
```

## Coexistence

- **Same target:** Swift Testing and XCTest can coexist in the same test target
- **Same file:** Both can be imported in the same file
- **Same type:** Cannot mix — a type is either `XCTestCase` or `@Suite`, never both
- **No `@Test` in XCTestCase:** Don't add `@Test` to methods in an `XCTestCase` subclass

### Cross-Framework Interoperability (ST-0021 — shipped in Swift 6.4)

Behavior of an `XCTAssert*` failure inside a `@Test` function, verified by running tests on both toolchains:

| Toolchain / mode | Result |
|---|---|
| Swift ≤ 6.3 | **Silently ignored — test passes.** False negative. |
| Swift 6.4, Limited mode (default when `swift-tools-version` < 6.4) | Passes **with warnings** ("Issue recorded" + "An API was misused") — visible, still a false negative |
| Swift 6.4, Complete mode (`swift-tools-version` ≥ 6.4, or `SWIFT_TESTING_XCTEST_INTEROP_MODE=complete`) | **Fails the test** — real interop |

The mode is controlled by `SWIFT_TESTING_XCTEST_INTEROP_MODE` (`none`/`limited`/`complete`/`strict`; strict turns misuse into `fatalError`). Interop also works the other direction in Complete mode: `#expect`, `Issue.record()`, `withKnownIssue`, and `Test.cancel()` function inside `XCTestCase` methods. `XCTSkip`, `XCTestExpectation`, `XCTWaiter`, and traits remain non-interoperable.

Regardless of mode: always use `#expect`/`#require` in `@Test` functions. Interop is a migration safety net, not a style.

## Migration Tips

1. **Start with new tests:** Write new tests using Swift Testing, leave existing XCTest as-is
2. **Migrate leaf tests first:** Tests with no shared setUp/tearDown are easiest
3. **Don't migrate UI tests:** XCUITest has no Swift Testing equivalent
4. **Don't migrate performance tests:** XCTMetric has no equivalent
5. **@MainActor suites:** When testing MainActor-isolated types, annotate the suite:

```swift
@MainActor
@Suite struct ViewModelTests {
    let sut = MyViewModel()  // @MainActor type
    @Test func initialState() {
        #expect(sut.isLoading == false)
    }
}
```
