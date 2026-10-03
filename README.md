# Swift Testing Skill

An agent skill for Apple's Swift Testing framework (`import Testing`), covering Swift 6.0-6.4 and Xcode 16-27. It works with any agent that reads the [Agent Skills](https://agentskills.io) format, including Claude Code and OpenAI Codex.

It focuses on what coding agents get wrong: tests that compile but pass when they should fail (`Task { }` in a test, asserting inside a callback, `XCTAssert*` inside `@Test`), the scope of `.serialized`, invented APIs (a `.repeating` trait, sub-minute time limits), and Swift 6.1-6.4 additions such as exit tests, image and `Transferable` attachments, `Test.cancel`, issue severity, and `CustomTestReflectable`. For XCTest migrations it includes a compact mapping and corrects consequential gaps in Apple's `modernize-tests` recipes.

The skill follows the repository's existing framework: it writes XCTest in XCTest targets unless asked to use Swift Testing or to migrate.

## Install

Codex and other agents that read `~/.agents/skills`:

```bash
git clone https://github.com/farkasseb/swift-testing-skill ~/.agents/skills/swift-testing
```

Claude Code reads `~/.claude/skills`. Clone there, or symlink the copy above:

```bash
mkdir -p ~/.claude/skills
ln -s ~/.agents/skills/swift-testing ~/.claude/skills/swift-testing
```

For a single project, put it in the repository's `.agents/skills/` (Codex) or `.claude/skills/` (Claude Code).

## Layout

```
SKILL.md                                   Target settings, false-pass review, reference routing
references/modern-apis.md                  Errors, exit tests, attachments, severity, cancellation, scoping and issue-handling traits
references/concurrency-and-structure.md    Suites and lifecycle, parallelism, confirmation, time limits, skipping, tags, parameterized tests
references/migration.md                    XCTest migration beyond the assertion mapping, XCTest interop, test plans, verification
evals/evals.json                           Focused prompts with review expectations
tests/run.sh                               Verification harness (see below)
```

## Verification

`tests/run.sh` runs on the installed release baseline, Xcode 26.6 / Swift 6.3.3, and Xcode 27.1 beta / Swift 6.4. Swift 6.4-only checks are explicitly skipped on 6.3. Select Xcode with `$XCODE` (an `.app` path), `$DEVELOPER_DIR`, or `xcode-select -p`:

```bash
XCODE=/Applications/Xcode-26.6.0.app TEST_LOG_DIR=/tmp/testing-release tests/run.sh
XCODE=/Applications/Xcode-27.1.0-Beta.app TEST_LOG_DIR=/tmp/testing-beta tests/run.sh
```

The suite compiles and runs the executable examples, checks callback timeout/cancellation and per-case scoping, and verifies package interoperability using process status, the named test outcome and runtime warnings. It also checks API/deployment availability in the installed SDK. Some snippets only check compilation; empty example bodies are not evidence of behavior.

The October 2026 audit additionally ran deliberately broken async/callback tests, shared-state suites, parameterized/scoped tests, and iOS simulator interop. Evidence distinguishes initial false passes, actual assertion failures, compiler errors and infrastructure/watchdog failures. A green suite does not prove every possible migration preserves behavior.

Audited libraries: Xcode 26.6 (Swift 6.3.3, Testing 1902) as the release baseline; Xcode 27.1 beta (Swift 6.4, Testing 2084) for the main audit. Xcode 27.0 RC has the same public Testing interfaces. Xcode 27.2 beta 2 reports Testing 2401 with the same public declarations.

## Evals

`evals/evals.json` holds prompts with graded expectations. Most target knowledge that models trained before the 6.3/6.4 releases get confidently wrong; others check migration correctness, behavior preservation, and the keep-XCTest boundary. Run each prompt with and without the skill, with web and documentation lookup disabled, so the difference measures the skill.

## Sources

- [Swift Testing documentation](https://developer.apple.com/documentation/testing/) and [swift-testing on GitHub](https://github.com/swiftlang/swift-testing)
- [Swift Testing evolution proposals](https://github.com/swiftlang/swift-evolution/tree/main/proposals/testing), ST-0001 through ST-0028
- [Meet Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10179/) and [Go further with Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10195/) (WWDC24)

## Contributing

PRs are welcome. Include a source (Apple documentation, an evolution proposal, or a reproducible test) for any behavioral claim.
