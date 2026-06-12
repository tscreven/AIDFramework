import Foundation

public struct ForecastResult {
    public let iob: [Decimal]
    public let cob: [Decimal]?
    public let uam: [Decimal]?
    public let zt: [Decimal]
    public let internalCob: [Decimal]
    public let internalUam: [Decimal]
    public let eventualGlucose: Decimal
    public let minForecastedGlucose: Decimal
    public let minIOBForecastedGlucose: Decimal
    public let minGuardGlucose: Decimal
    public let carbImpact: Decimal
    public let remainingCarbImpactPeak: Decimal
    public let adjustedCarbRatio: Decimal

    public init(
        iob: [Decimal],
        cob: [Decimal]?,
        uam: [Decimal]?,
        zt: [Decimal],
        internalCob: [Decimal],
        internalUam: [Decimal],
        eventualGlucose: Decimal,
        minForecastedGlucose: Decimal,
        minIOBForecastedGlucose: Decimal,
        minGuardGlucose: Decimal,
        carbImpact: Decimal,
        remainingCarbImpactPeak: Decimal,
        adjustedCarbRatio: Decimal
    ) {
        self.iob = iob
        self.cob = cob
        self.uam = uam
        self.zt = zt
        self.internalCob = internalCob
        self.internalUam = internalUam
        self.eventualGlucose = eventualGlucose
        self.minForecastedGlucose = minForecastedGlucose
        self.minIOBForecastedGlucose = minIOBForecastedGlucose
        self.minGuardGlucose = minGuardGlucose
        self.carbImpact = carbImpact
        self.remainingCarbImpactPeak = remainingCarbImpactPeak
        self.adjustedCarbRatio = adjustedCarbRatio
    }
}

public struct ForecastSelectionResult {
    public let minIOBForecastGlucose: Decimal
    public let minCOBForecastGlucose: Decimal
    public let minUAMForecastGlucose: Decimal
    public let minIOBGuardGlucose: Decimal
    public let minCOBGuardGlucose: Decimal
    public let minUAMGuardGlucose: Decimal
    public let minZTGuardGlucose: Decimal
    public let maxIOBForecastGlucose: Decimal
    public let maxCOBForecastGlucose: Decimal
    public let maxUAMForecastGlucose: Decimal
    public let lastIOBForecastGlucose: Decimal
    public let lastCOBForecastGlucose: Decimal
    public let lastUAMForecastGlucose: Decimal
    public let lastZTForecastGlucose: Decimal
}

public struct ForecastBlendingResult {
    public let minForecastedGlucose: Decimal
    public let avgForecastedGlucose: Decimal
    public let minGuardGlucose: Decimal

    public init(minForecastedGlucose: Decimal, avgForecastedGlucose: Decimal, minGuardGlucose: Decimal) {
        self.minForecastedGlucose = minForecastedGlucose
        self.avgForecastedGlucose = avgForecastedGlucose
        self.minGuardGlucose = minGuardGlucose
    }
}
