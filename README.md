# Swift Testing Skill

AI skill reference for Apple's Swift Testing framework (coverage through Swift 6.4 / Xcode 27) — corrects common XCTest mistakes AI models make with `@Test`, `#expect`, `#require`, `confirmation()`, and migration patterns, plus the Swift 6.3/6.4 additions models don't know: image and `Transferable` attachments, `Test.cancel()`, issue severity, `CustomTestReflectable`, per-test-case repetitions, and the ST-0021 XCTest interop behavior change.

**This skill is slightly opinionated — it favors Swift Testing over XCTest for new test targets, struct-based suites over class-based, `confirmation()` over callback-based patterns, and `withKnownIssue` over disabling tests. These opinions align with Apple's recommended direction, but existing XCTest codebases should stay on XCTest unless explicitly migrating.**

## Why this exists

AI models know Swift Testing exists, but they consistently generate wrong patterns. They fall back to XCTest boilerplate (`class FooTests: XCTestCase`), wrap async code in `Task { }` (which silently passes broken tests), use `XCTAssertThrowsError` instead of `#expect(throws:)`, reach for `XCTestExpectation` instead of `confirmation()`, and put `try`/`await` in the wrong place around macros.

These aren't subtle issues — they produce tests that compile but silently pass when they should fail, or fail with misleading diagnostics.

### What AI models get wrong vs. what this skill corrects

| Topic | What AI says (wrong) | What's actually correct |
|-------|---------------------|------------------------|
| Test structure | `class FooTests: XCTestCase` | `@Suite struct FooTests` with `@Test` methods |
| Async testing | `Task { #expect(...) }` | Mark function `async` directly — `Task { }` silently passes |
| Error assertions | `XCTAssertThrowsError` | `#expect(throws: MyError.self) { try foo() }` |
| Async expectations | `XCTestExpectation` + `waitForExpectations` | `confirmation { confirm in ... }` |
| `#require` usage | `let x = #require(opt)` | `let x = try #require(opt)` — `#require` throws |
| `try`/`await` placement | `try #expect(foo())` | `#expect(try foo())` — inside the macro |
| Tags | `.tags("networking")` | `.tags(.networking)` via `extension Tag` declaration |
| Known failures | `.disabled("known bug")` | `withKnownIssue { }` — tracks without disabling |
| XCTAssert inside @Test | "Silently ignored" or "works fine" | Toolchain-dependent (ST-0021): silent pass ≤6.3, warnings on 6.4 Limited mode, real failure on 6.4 Complete mode |
| Image attachments | "Encode to PNG Data manually" | `Attachment.record(image, named:as: .png)` directly since Swift 6.3 |
| Rerunning flaky tests | Invents a `.repeating(...)` trait | No trait exists — `swift test --repeat-until fail --maximum-repetitions N` (Swift 6.4 CLI) |
| Skipping mid-test | "Not possible / use .disabled" | `try Test.cancel("reason")` since Swift 6.3; cancels only the current case in parameterized tests |

## Installation

### Claude Code (as a skill)

```bash
mkdir -p ~/.claude/skills/swift-testing
cp SKILL.md ~/.claude/skills/swift-testing/
cp -r references ~/.claude/skills/swift-testing/
```

The skill activates automatically when your conversation involves Swift Testing APIs (`import Testing`, `@Test`, `@Suite`, `#expect`, `#require`, etc.).

### Codex CLI (as agents)

```bash
mkdir -p ~/.agents/skills/swift-testing
cp SKILL.md ~/.agents/skills/swift-testing/
cp -r references ~/.agents/skills/swift-testing/
```

### Other AI tools (as context)

The files are plain markdown — feed them as context to any AI coding assistant. Each reference file is self-contained:

- **Core APIs**: `references/api-reference.md` — `@Test`, `@Suite`, `#expect`, `#require`, `confirmation()`, `withKnownIssue`, exit testing, attachments
- **Async patterns**: `references/async-and-concurrency.md` — async tests, `confirmation()` deep-dive, serialization scope, `@MainActor`, time limits
- **Parameterized tests**: `references/parameterized-testing.md` — `arguments:`, zip, Cartesian product, `CustomTestStringConvertible`
- **Traits and tags**: `references/traits-and-tags.md` — `.serialized`, `.timeLimit`, `.disabled`, `.bug`, `.tags`, custom traits
- **XCTest migration**: `references/xctest-migration.md` — full assertion mapping table, lifecycle changes, coexistence rules

## File structure

```
SKILL.md                              # Router + 15 high-risk mistakes + decision trees + "Doesn't Exist" guards + behavioral rules
references/
├── api-reference.md                  # Complete API reference incl. attachments, CustomTestReflectable, repetitions
├── async-and-concurrency.md          # Async testing patterns
├── parameterized-testing.md          # Parameterized testing patterns
├── traits-and-tags.md                # Traits and tagging system
└── xctest-migration.md               # XCTest migration guide + verified ST-0021 interop matrix
```

## Sources

Synthesized from primary Apple sources and Swift Evolution proposals:

- [Swift Testing documentation](https://developer.apple.com/documentation/testing/) — Apple's official framework reference
- [Meet Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10179/) — WWDC24-10179: introduction to the framework
- [Go further with Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10195/) — WWDC24-10195: parameterized tests, traits, suites
- [What's new in Swift Testing](https://developer.apple.com/videos/play/wwdc2025/232/) — WWDC25-232: exit testing, attachments, `@Test(arguments:)` improvements
- [swift-testing on GitHub](https://github.com/swiftlang/swift-testing) — open-source repository
- [SE-0429: A new approach to testing in Swift](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0429-swift-testing.md) — Swift Evolution proposal
- Swift Testing evolution proposals ST-0012 through ST-0024 (full text verified), including [ST-0016 test cancellation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0016-test-cancellation.md), [ST-0017 image attachment consolidation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0017-image-attachment-consolidation.md), [ST-0021 XCTest interoperability](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0021-targeted-interoperability-swift-testing-and-xctest.md), [ST-0023 Transferable attachments](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0023-attachments-transferable.md), and [ST-0024 per-test-case repetitions](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0024-per-test-case-repetitions.md)

**Empirical verification (Jul 2026):** version gates and behavioral claims were verified by compiling and running probe packages against Swift 6.3.3 (Xcode 26.6) and Swift 6.4 (Xcode 27 beta 2) — including the ST-0021 interop behavior matrix, which was observed by executing failing XCTAssert calls inside @Test functions under each interop mode, not inferred from proposal text. The deployment floor was read from the shipped Testing.framework binaries (`otool -l` minos): iOS 14+ in Xcode 26.6, raised to iOS 17+ in Xcode 27.

## Evals

`evals/evals.json` contains benchmark prompts with graded assertions. Each targets a knowledge delta where a model with stale training data gives a confidently wrong answer (inventing a `.repeating` trait, claiming XCTAssert-in-@Test works, manual image encoding). Run them by giving each prompt to a model with and without skill access, forbidding web/documentation lookup so the delta measures the skill.

## Contributing

Found an inaccuracy, a missing pattern, or encountered a new mistake AI models make with Swift Testing? PRs welcome. Please include the source (Apple doc URL, Swift Evolution proposal, or your own experience) for any additions.
