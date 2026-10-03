// Stand-in types so the documentation samples compile unchanged.
import CoreGraphics
import CoreTransferable
import Foundation
import Testing

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}

// SKILL.md / modern-apis.md
enum ParseError: Error, Equatable {
    case badHeader
    var line: Int { 3 }
}
func parse(_ data: Data) throws { if data.isEmpty { throw ParseError.badHeader } }
let data = Data()
let valid = Data([1])

struct Inventory {
    init(count: Int) { precondition(count >= 0, "negative count") }
}

struct Report: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { _ in Data("%PDF-1.4".utf8) }
    }
}
let document = Report()

func makeImage() -> CGImage {
    let context = CGContext(
        data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}
let image = makeImage()
let rendered = makeImage()
let reference = makeImage()
func matches(_ a: CGImage, _ b: CGImage) -> Bool { a.width == b.width }

actor Server { var isReachable: Bool { true } }
let server = Server()

private let databaseSerials = Locked(0)

final class Database: Sendable {
    let serial = databaseSerials.withLock { $0 += 1; return $0 }
    private let destroyed = Locked(false)
    var isDestroyed: Bool { destroyed.withLock { $0 } }
    static func makeTemporary() async throws -> Database { Database() }
    func destroy() async throws { destroyed.withLock { $0 = true } }
    func insert(_ row: String) async throws {}
}

let deviceName = "Mac"
struct Invoice { let id = 1; let total = 2.5 }

// concurrency-and-structure.md
struct Cart {
    private(set) var count = 0
    mutating func add(_ item: String) { count += 1 }
}
final class Processor: @unchecked Sendable {
    var onItem: (String) -> Void = { _ in }
    func process(_ items: [String]) async { items.forEach(onItem) }
}
let processor = Processor()
final class Emitter: @unchecked Sendable {
    var onEvent: () -> Void = {}
    func run() async { onEvent() }
}
let emitter = Emitter()
enum FeatureFlags { static let newParser = true }
enum Region: Sendable { case us, eu }

// migration.md
struct Order { let total = 1; let items = ["apple"] }
enum APIError: Error, Equatable { case unauthorized, badRequest(String) }
final class Client: Sendable { func fetch() async throws { throw APIError.badRequest("body") } }
let client = Client()
let expectedBody = "body"

final class Loader: Sendable {
    func load(completion: @escaping @Sendable (Result<Int, any Error>) -> Void) {
        DispatchQueue.global().async { completion(.success(42)) }
    }
}
let sut = Loader()

final class Gate: Sendable {
    private let opened = Locked(false)
    var isOpen: Bool { opened.withLock { $0 } }
    func open() { opened.withLock { $0 = true } }
}
final class FeatureService: Sendable {
    let gate: Gate
    init(gate: Gate) { self.gate = gate }
    func isEnabled() async -> Bool {
        while !gate.isOpen { await Task.yield() }
        return true
    }
}
