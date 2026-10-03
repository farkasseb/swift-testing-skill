// Samples from SKILL.md and references/concurrency-and-structure.md.
import Foundation
import Testing

func a() throws -> Int { 1 }
func b() throws -> Int { 1 }

@Test func tryBeforeTheMacro() throws {
    try #expect(a() == b())
}

extension Tag {
    @Tag static var slow: Self
    @Tag static var networking: Self
}

@Test(.tags(.slow)) func tagged() {}

struct CartTests {
    var cart = Cart()

    @Test mutating func `Adding an item increases the count`() {
        cart.add("apple")
        #expect(cart.count == 1)
    }
}

@Suite(.serialized) struct DisplayTests {       // one shared-state group
    @Suite struct NumberEntry { @Test func entersDigit() {} }
    @Suite struct DecimalPoint { @Test func addsPoint() {} }
}

@Suite(.serialized) struct ConfirmationSamples {
    @Test func counts() async {
        await confirmation("item processed", expectedCount: 3) { confirm in
            processor.onItem = { _ in confirm() }
            await processor.process(["a", "b", "c"])
        }
    }

    @Test func ranges() async {
        await confirmation(expectedCount: 1...) { confirm in       // Swift 6.1: ranges
            emitter.onEvent = { confirm() }
            await emitter.run()
        }
    }
}

@Test(.timeLimit(.minutes(1))) func limited() {}

@Test(.disabled("Waiting on FB12345"))             func a1() { }
@Test(.enabled(if: FeatureFlags.newParser))       func b1() { }
@available(macOS 99, iOS 99, *) @Test             func availabilityGated() { Issue.record("must be skipped") }
@Test(.bug("https://example.com/issues/42"))     func d1() { }

@Suite(.tags(.networking)) struct APITests { @Test func fetches() {} }

struct PricingTests {
    static let prices: [Decimal] = [0, 9.99, 100]
    static let regions = [Region.us, .eu]

    @Test(arguments: prices)
    func nonNegative(price: Decimal) { #expect(price >= 0) }

    @Test(arguments: regions, prices)                   // Cartesian product: 6 cases
    func taxIsApplied(region: Region, price: Decimal) { /* ... */ }

    @Test(arguments: zip([1, 2, 3], [2, 4, 6]))          // paired: 3 cases
    func doubles(input: Int, expected: Int) { #expect(input * 2 == expected) }

    @Test(arguments: regions, Array(zip([1, 2], [3, 4])))
    func zippedSecondArgument(region: Region, pair: (Int, Int)) { }
}

@Test(.serialized, arguments: [1, 2]) func serialCases(n: Int) {}
