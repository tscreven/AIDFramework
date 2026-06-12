import Testing
@testable import OrefSwiftCLI
import OrefSwiftModels

@Suite("DirectionCalculator")
struct DirectionCalculatorTests {
    @Test("tripleUp for delta > 17")
    func tripleUp() {
        #expect(DirectionCalculator.direction(from: 18) == .tripleUp)
        #expect(DirectionCalculator.direction(from: 30) == .tripleUp)
    }

    @Test("doubleUp for delta 10-17")
    func doubleUp() {
        #expect(DirectionCalculator.direction(from: 10) == .doubleUp)
        #expect(DirectionCalculator.direction(from: 17) == .doubleUp)
    }

    @Test("singleUp for delta 5-9")
    func singleUp() {
        #expect(DirectionCalculator.direction(from: 5) == .singleUp)
        #expect(DirectionCalculator.direction(from: 9) == .singleUp)
    }

    @Test("fortyFiveUp for delta 3-4")
    func fortyFiveUp() {
        #expect(DirectionCalculator.direction(from: 3) == .fortyFiveUp)
        #expect(DirectionCalculator.direction(from: 4) == .fortyFiveUp)
    }

    @Test("flat for delta -2 to 2")
    func flat() {
        #expect(DirectionCalculator.direction(from: 2) == .flat)
        #expect(DirectionCalculator.direction(from: 0) == .flat)
        #expect(DirectionCalculator.direction(from: -2) == .flat)
    }

    @Test("fortyFiveDown for delta -3 to -4")
    func fortyFiveDown() {
        #expect(DirectionCalculator.direction(from: -3) == .fortyFiveDown)
        #expect(DirectionCalculator.direction(from: -4) == .fortyFiveDown)
    }

    @Test("singleDown for delta -5 to -9")
    func singleDown() {
        #expect(DirectionCalculator.direction(from: -5) == .singleDown)
        #expect(DirectionCalculator.direction(from: -9) == .singleDown)
    }

    @Test("doubleDown for delta -10 to -17")
    func doubleDown() {
        #expect(DirectionCalculator.direction(from: -10) == .doubleDown)
        #expect(DirectionCalculator.direction(from: -17) == .doubleDown)
    }

    @Test("tripleDown for delta < -17")
    func tripleDown() {
        #expect(DirectionCalculator.direction(from: -18) == .tripleDown)
        #expect(DirectionCalculator.direction(from: -30) == .tripleDown)
    }

    @Test("boundary values at each threshold")
    func boundaries() {
        // delta > 17 is tripleUp, so 17 is NOT tripleUp
        #expect(DirectionCalculator.direction(from: 17) == .doubleUp)
        // delta > 9 is doubleUp, so 9 is NOT doubleUp
        #expect(DirectionCalculator.direction(from: 9) == .singleUp)
        // delta > 4 is singleUp, so 4 is NOT singleUp
        #expect(DirectionCalculator.direction(from: 4) == .fortyFiveUp)
        // delta > 2 is fortyFiveUp, so 2 is NOT fortyFiveUp
        #expect(DirectionCalculator.direction(from: 2) == .flat)
        // delta >= -2 is flat, so -2 IS flat
        #expect(DirectionCalculator.direction(from: -2) == .flat)
        // delta >= -4 is fortyFiveDown, so -4 IS fortyFiveDown
        #expect(DirectionCalculator.direction(from: -4) == .fortyFiveDown)
        // delta >= -9 is singleDown, so -9 IS singleDown
        #expect(DirectionCalculator.direction(from: -9) == .singleDown)
        // delta >= -17 is doubleDown, so -17 IS doubleDown
        #expect(DirectionCalculator.direction(from: -17) == .doubleDown)
    }
}
