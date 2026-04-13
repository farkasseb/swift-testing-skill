# Parameterized Testing

## Basic Parameterized Test

Instead of duplicating tests for different inputs, use `arguments:`:

```swift
@Test(arguments: [1, 2, 3, 4, 5])
func isPositive(value: Int) {
    #expect(value > 0)
}
// Creates 5 separate test cases, each run independently
```

## Single Collection

```swift
@Test(arguments: ["hello", "world", "swift"])
func notEmpty(word: String) {
    #expect(!word.isEmpty)
}

// With display name
@Test("Adding zero is identity", arguments: [5.0, 0.0, -7.0])
func addZero(x: Double) throws {
    #expect(try BinaryOperator.add.operation(x, 0) == x)
}
```

## Two Collections (Cartesian Product)

Two argument collections create a Cartesian product — every combination is tested:

```swift
static let operations: [BinaryOperator] = [.add, .subtract]
static let values: [Double] = [5, 0, -7]

@Test(arguments: operations, values)
func additiveIdentity(op: BinaryOperator, x: Double) throws {
    #expect(try op.operation(x, 0) == x)
}
// Runs: add+5, add+0, add+-7, subtract+5, subtract+0, subtract+-7 (6 cases)
```

## Maximum 2 Argument Collections

Swift Testing restricts parameterized tests to **at most 2 argument collections**. More than 2 causes combinatorial explosion.

```swift
// WRONG — 3 collections, won't compile
@Test(arguments: ops, values1, values2) // ERROR
func test(op: Op, x: Double, y: Double) { ... }

// CORRECT — use zip or wrapper types
@Test(arguments: ops, Array(zip(values1, values2)))
func test(op: Op, pair: (Double, Double)) { ... }
```

## zip() for Paired Arguments

Use `zip()` when you want paired (1:1) arguments, not Cartesian product:

```swift
static let inputs = [1.0, 2.0, 3.0]
static let expected = [2.0, 4.0, 6.0]

@Test(arguments: zip(inputs, expected))
func doubleValue(input: Double, expected: Double) {
    #expect(input * 2 == expected)
}
// Runs: (1,2), (2,4), (3,6) — NOT all 9 combinations
```

**When zip is one of two arguments**, wrap in `Array()`:

```swift
@Test(arguments: operations, Array(zip(samples, samples.reversed())))
func commutative(op: BinaryOperator, pair: (Double, Double)) throws {
    let (x, y) = pair
    #expect(try op.operation(x, y) == op.operation(y, x))
}
```

## Instance Members Unavailable in arguments:

`@Test(arguments:)` evaluates before any suite instance is created, so instance members cannot be referenced. Use `static` properties, literals, or `try`/`await` expressions.

```swift
// WRONG — instance member
let samples = [1, 2, 3]
@Test(arguments: samples) func test(x: Int) { ... }
// ERROR: Instance member 'samples' cannot be used on type 'Bonus'

// CORRECT — static member
static let samples = [1, 2, 3]
@Test(arguments: samples) func test(x: Int) { ... }

// ALSO CORRECT — literal
@Test(arguments: [1, 2, 3]) func test(x: Int) { ... }
```

Static computed properties also work (useful for random test data):

```swift
static let randomSamples: [Double] = {
    var doubles: [Double] = []
    for _ in 0...3 {
        doubles.append(Double.random(in: -10...10))
    }
    return doubles
}()
```

## Arguments Must Be Sendable

Since parameterized tests run in parallel by default, all argument types must conform to `Sendable`:

```swift
// OK — Int, Double, String, enums are Sendable
@Test(arguments: [1, 2, 3]) func test(x: Int) { ... }

// OK — enum conforming to Sendable
enum Op: Sendable { case add, subtract }
@Test(arguments: [Op.add, .subtract]) func test(op: Op) { ... }

// ERROR — non-Sendable class
class Config { var value = 0 }
@Test(arguments: [Config()]) func test(c: Config) { ... }  // won't compile
```

## CustomTestStringConvertible

Controls how arguments appear in the Test Navigator. Without it, complex types show their full `debugDescription`.

```swift
struct Pair {
    let x: Double
    let y: Double
}

extension Pair: CustomTestStringConvertible {
    var testDescription: String {
        "(\(x), \(y))"
    }
}

// Now Test Navigator shows: commutative(op:pair:) → +, (3.5, -2.1)
// Instead of: +, Pair(x: 3.5, y: -2.1)
```

For types you don't own, use `@retroactive`:

```swift
extension Double: @retroactive CustomTestStringConvertible {
    public var testDescription: String {
        String(format: "%.2f", self)
    }
}
```

**Note:** Tuples cannot conform to `CustomTestStringConvertible`. Use wrapper types instead.

## CustomTestArgumentEncodable

For selectively re-running specific test cases in Xcode, arguments should conform to one of:
- `CustomTestArgumentEncodable`
- `RawRepresentable` (where `RawValue` is encodable)
- `Encodable`
- `Identifiable`

Most standard types (Int, String, Double) already satisfy this.

## Wrapper Types Pattern

When tuples are used as arguments, their output in the Test Navigator can be unreadable. Create wrapper types with `CustomTestStringConvertible`:

```swift
// Instead of: (3.881153739630..., -1.092247191421...)
// Show: (3.88, -1.09)

struct Single {
    let x: Double
}

extension Single: CustomTestStringConvertible {
    var testDescription: String {
        String(format: "%.2f", x)
    }
}

func wrap(_ doubles: [Double]) -> [Single] {
    doubles.map { Single(x: $0) }
}

@Test(arguments: operations, wrap(samples + randomSamples))
func identity(op: BinaryOperator, value: Single) throws {
    #expect(try op.operation(value.x, 0) == value.x)
}
```
