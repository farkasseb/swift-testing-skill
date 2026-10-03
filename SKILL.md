---
name: swift-testing
description: "Swift Testing (import Testing, @Test, #expect) through Swift 6.4 / Xcode 27: writing, reviewing, or migrating tests, including false passes, async callbacks, shared state, parameterized tests and traits, cancelling tests, flaky reruns, warnings and attachments, and XCTAssert inside @Test. Not for XCUITest, performance tests, or unrelated XCTest-only edits."
---

# Swift Testing

Use the target's existing framework when extending tests. Migrate XCTest only when asked. UI automation and `measure` tests stay in XCTest; other methods can migrate separately. Both frameworks can share a target or file, but `@Test` cannot live inside an `XCTestCase` subclass.

## Check the target

Keep these inputs separate:

- **Compiler and bundled Testing library:** `swift --version`, the test log's Testing Library Version, and the selected Xcode's `Testing.swiftinterface`. A compiler version alone does not identify the library build.
- **Package manifest:** `swift-tools-version` controls the default XCTest interop mode in Swift 6.4 packages. It is not the Swift language mode.
- **Target settings:** language mode, default actor isolation, and upcoming concurrency features affect the test and its helpers. Read the test target's settings, not only the app's.
- **Deployment floor:** the bundled Testing framework's runtime floor is separate from individual API availability. Installed Xcode 26.6 has an iOS 14 / macOS 14 floor; Xcode 27 has iOS 17 / macOS 14. Transferable attachments need newer OS versions still.

Audited toolchains: [README verification](README.md#verification). Version gates: [version-specific APIs](references/modern-apis.md).

## Review for meaningful failures

1. **Join the work.** `Task { }` does not make a test wait. Await the operation or the retained task's value before returning.
2. **Observe callback completion.** Assertions inside a callback can be skipped entirely. Await a bounded result, then assert; a bare continuation hangs if the callback never fires. `confirmation` checks counts when its body returns, it does not wait. See [callback migration](references/migration.md#completion-handlers).
3. **Check interop before trusting green.** On Swift 6.3, failing `XCTAssert` inside `@Test` is ignored. Swift 6.4's limited mode warns but still passes; complete mode fails. Replace assertions with `#expect` / `#require`, including those hidden inside mock verifiers and helpers. See [the runtime matrix](references/migration.md#xctest-interop).
4. **Contain shared state.** `.serialized` covers its suite's descendants or a parameterized test's cases, not sibling suites. `@MainActor` does not serialize whole async tests. Prefer independent fixtures; otherwise group all users under one serialized parent. See [parallelism](references/concurrency-and-structure.md#parallelism-and-serialized).
5. **Preserve what migration verifies.** Keep timeout bounds, error payload checks, independent assertions after mismatches, and repeated calls on the same instance. Parameterizing a stateful loop changes its meaning. Read [migration](references/migration.md) before converting.
6. **Prove a test catches the relevant bug.** For suspicious green tests or a behavior-sensitive migration, run a deliberate wrong result or missing completion and inspect the named test's failure. Compilation and total test counts alone cannot establish coverage.

A correct existing test needs no rewrite. `try #expect(f() == expected)` and `await #expect(store.count() == 3)` are valid; inside-the-parentheses forms are valid too. Swift rejects `#expect(try a() == try b())`; use one `try` for the whole expression.

## Read for the task

- [Concurrency and structure](references/concurrency-and-structure.md): lifecycle, actor isolation, serialization, confirmations, time limits, arguments and tags.
- [Migration](references/migration.md): assertion mapping, callbacks, teardown, helpers, test plans, and XCTest interop. Audit Apple's `modernize-tests` recipes against these claim-specific corrections and the actual target; it is not a second authority that must be loaded.
- [Version-specific APIs](references/modern-apis.md): returned errors, scoping traits, attachments, cancellation, warnings, exit tests, repetition and unavailable APIs.

For generated mocks or DI, inspect the project's installed version and generated code. A per-test container trait can isolate registrations without serializing tests; it does not isolate pre-existing shared objects or detached tasks. Serialization between tests does not make a mock safe for concurrent calls within one test. Consult the relevant mocking/DI skill for those library-specific details.
