import Foundation

public struct AdjustedGlucoseTargets {
    public var minGlucose: Decimal
    public var maxGlucose: Decimal
    public var targetGlucose: Decimal

    public init(minGlucose: Decimal, maxGlucose: Decimal, targetGlucose: Decimal) {
        self.minGlucose = minGlucose
        self.maxGlucose = maxGlucose
        self.targetGlucose = targetGlucose
    }
}
