import Foundation
import OrefSwiftModels

enum DirectionCalculator {
    static func direction(from delta: Int) -> BloodGlucose.Direction {
        if delta > 17 { return .tripleUp }
        if delta > 9 { return .doubleUp }
        if delta > 4 { return .singleUp }
        if delta > 2 { return .fortyFiveUp }
        if delta >= -2 { return .flat }
        if delta >= -4 { return .fortyFiveDown }
        if delta >= -9 { return .singleDown }
        if delta >= -17 { return .doubleDown }
        return .tripleDown
    }
}
