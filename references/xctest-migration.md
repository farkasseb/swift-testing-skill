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
| `XCTAssertThrowsError` | `#expect(throws: Type.self) { }` | Returns the error for inspection (ST-0006) |
| `XCTAssertNoThrow` | `#expect(throws: Never.self) { }` | |
| `XCTExpectFailure` | `withKnownIssue { }` | Fails when issue is fixed |
| `XCTSkip` / `XCTSkipIf` | `.disabled()` / `.enabled(if:)` (pre-start) or `try Test.cancel()` (runtime, Swift 6.3) | |
| `XCTestExpectation` | `confirmation()` | Block-scoped |
| `waitForExpectations(timeout:)` | (built into confirmation) | |
| `XCTFail("msg")` | `Issue.record("msg")` | |
| `addTeardownBlock { }` | `deinit` or custom `TestScoping` trait | |
| `measure { }` | Not available | Use XCTest for perf tests |

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

### Cross-Framework Interoperability (ST-0021 — Accepted, not yet shipped)

ST-0021 will add formal runtime interop so XCTAssert\* works inside @Test functions and vice versa. **Until it ships, XCTAssert\* inside @Test is silently ignored — a false negative.** Always use `#expect`/`#require` in @Test functions.

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
