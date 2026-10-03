// Samples from references/modern-apis.md.
import CoreGraphics
import Foundation
import Testing

@Test func errorSamples() throws {
    #expect(throws: ParseError.badHeader) { try parse(data) }   // exact Equatable value
    #expect(throws: Never.self) { try parse(valid) }            // must not throw

    let error = #expect(throws: ParseError.self) { try parse(data) }
    #expect(error?.line == 3)                                   // test continues on mismatch

    let fatal = try #require(throws: ParseError.self) { try parse(data) }
    #expect(fatal.line == 3)                                    // test stopped on mismatch
}

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

@Test func exitConditionsAndObservation() async {
    let result = await #expect(processExitsWith: .signal(SIGABRT), observing: [\.standardErrorContent]) {
        abort()
    }
    _ = result?.standardErrorContent
    await #expect(processExitsWith: .exitCode(3)) { exit(3) }
}

struct Snapshot: Codable, Attachable { var rows: [String] }

@Test func export() {
    Attachment.record(Snapshot(rows: ["a"]), named: "snapshot.json")
}

@Test func imageAttachments() {
    Attachment.record(image, named: "rendered", as: .png)
    Attachment.record(image, named: "rendered", as: .jpeg(withEncodingQuality: 0.8))
}

#if compiler(>=6.4)
@available(macOS 15.2, *)
@Test func transferableAttachment() async throws {
    let attachment = try await Attachment(exporting: document, as: .pdf, named: "report.pdf")
    Attachment.record(attachment)
}

#endif

@Test func conditionalAttachment() {
    if !matches(rendered, reference) {
        Attachment.record(rendered, named: "rendered", as: .png)
        Issue.record("Rendered image differs from the reference")
    }
}

@Test func issueSamples() {
    withKnownIssue {
        Issue.record("Unexpected state")                                   // fails the test
    }
    Issue.record("Match was 93%, threshold 90%", severity: .warning)   // Swift 6.3: reported, does not fail
}

@Test func syncsWithServer() async throws {
    guard await server.isReachable else {
        try Test.cancel("Server unreachable")
    }
    // ...
}

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

@Test(.compactMapIssues { issue in
    var issue = issue
    issue.comments.append("Device: \(deviceName)")
    return issue
})
func rendersOnDevice() { /* ... */ }

@Test(.filterIssues { issue in issue.severity == .error })
func ignoresWarnings() { Issue.record("dropped", severity: .warning) }

#if compiler(>=6.4)
extension Invoice: CustomTestReflectable {
    var customTestMirror: Mirror {
        Mirror(self, children: ["id": id, "total": total])
    }
}
#endif
