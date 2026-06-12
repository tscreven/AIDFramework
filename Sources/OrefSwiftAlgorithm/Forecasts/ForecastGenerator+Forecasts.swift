import Foundation
import OrefSwiftModels

extension ForecastGenerator {
    static func forecastIOB(
        startingGlucose: Decimal,
        glucoseImpactSeries: [Decimal],
        iobData: [IobResult],
        carbImpact: Decimal,
        dynamicIsfState: DynamicIsfState,
        insulinFactor: Decimal?,
        tdd: Decimal,
        adjustmentFactorLogrithmic: Decimal
    ) -> IndividualForecast {
        var result = [startingGlucose]
        var rawResult = [startingGlucose]
        var minGuardGlucose = Decimal(999)
        for (glucoseImpact, iob) in zip(glucoseImpactSeries, iobData) {
            let forecastedDeviation = carbImpact * (1 - min(1, Decimal(result.count) / (60 / 5)))
            let lastForecast = result.last!
            let next: Decimal
            if let insulinFactor = insulinFactor, dynamicIsfState == .logrithmic {
                let adjustedGlucoseImpact = adjustedGlucoseImpactForLogrithmicDynamicIsf(
                    lastForecast: lastForecast,
                    insulinFactor: insulinFactor,
                    tdd: tdd,
                    adjustmentFactorLogrithmic: adjustmentFactorLogrithmic,
                    iobActivity: iob.activity
                )
                next = lastForecast + adjustedGlucoseImpact + forecastedDeviation
            } else {
                next = lastForecast + glucoseImpact.jsRounded(scale: 2) + forecastedDeviation
            }
            if result.count < 48 { result.append(next) }
            if next < minGuardGlucose { minGuardGlucose = next.jsRounded() }
            rawResult.append(next)
        }
        let clampedResult = result.map { $0.clamp(lowerBound: 39, upperBound: 401) }

        return IndividualForecast(
            forecasts: ForecastGenerator.trimFlatTails(clampedResult, lookback: 13),
            minGuardGlucose: minGuardGlucose,
            rawForecasts: rawResult,
            duration: nil
        )
    }

    static func forecastCOB(
        startingGlucose: Decimal,
        glucoseImpactSeries: [Decimal],
        carbImpact: Decimal,
        carbImpactParams: CarbImpactParams
    ) -> IndividualForecast {
        var result = [startingGlucose]
        var rawResult = [startingGlucose]

        var minGuardGlucose = Decimal(999)
        for glucoseImpact in glucoseImpactSeries {
            let forecastedDeviation = carbImpact * (1 - min(1, Decimal(result.count) / (60 / 5)))

            let decayFactor = max(0, 1 - Decimal(result.count) / max(carbImpactParams.carbImpactDuration * 2, Decimal(1)))
            let forecastedCarbImpact = max(0, max(0, carbImpact) * decayFactor)

            let intervals = min(Decimal(result.count), carbImpactParams.remainingCarbAbsorptionTime * 12 - Decimal(result.count))
            let triangle = max(
                0,
                intervals / (carbImpactParams.remainingCarbAbsorptionTime / 2 * 12) * carbImpactParams.remainingCarbImpactPeak
            )

            let next = result.last!
                + glucoseImpact.jsRounded(scale: 2)
                + min(0, forecastedDeviation)
                + forecastedCarbImpact
                + triangle

            if result.count < 48 { result.append(next) }
            if next < minGuardGlucose { minGuardGlucose = next.jsRounded() }
            rawResult.append(next)
        }

        let clampedResult = result.map { $0.clamp(lowerBound: 39, upperBound: 1500) }

        return IndividualForecast(
            forecasts: ForecastGenerator.trimFlatTails(clampedResult, lookback: 13),
            minGuardGlucose: minGuardGlucose,
            rawForecasts: rawResult,
            duration: nil
        )
    }

    static func forecastUAM(
        startingGlucose: Decimal,
        glucoseImpactSeries: [Decimal],
        mealData: ComputedCarbs,
        uamCarbImpact: Decimal,
        carbImpact: Decimal,
        iobData: [IobResult],
        dynamicIsfState: DynamicIsfState,
        insulinFactor: Decimal?,
        tdd: Decimal,
        adjustmentFactorLogrithmic: Decimal
    ) -> IndividualForecast {
        var result = [startingGlucose]
        var rawResult = [startingGlucose]
        var uamDuration: Decimal = 0

        let slopeFromDeviations = min(
            mealData.slopeFromMaxDeviation.jsRounded(scale: 2),
            -mealData.slopeFromMinDeviation.jsRounded(scale: 2) / 3
        )
        let ticksInThreeHours: Decimal = 36 // 3 * 60 / 5

        let unannouncedCarbImpact = uamCarbImpact
        var minGuardGlucose = Decimal(999)

        for (glucoseImpact, iob) in zip(glucoseImpactSeries, iobData) {
            let forecastedDeviation = carbImpact * (1 - min(1, Decimal(result.count) / (60 / 5)))

            let forecastedUnannouncedCarbImpactSlope = max(
                0,
                unannouncedCarbImpact + Decimal(result.count) * slopeFromDeviations
            )

            let maxForecastedUnannouncedCarbImpact = max(
                0,
                unannouncedCarbImpact * (1 - Decimal(result.count) / ticksInThreeHours)
            )
            let forecastedUnannouncedCarbImpact = min(
                forecastedUnannouncedCarbImpactSlope,
                maxForecastedUnannouncedCarbImpact
            )

            if forecastedUnannouncedCarbImpact > 0 {
                uamDuration = (Decimal(result.count) + 1) * 5 / 60
            }

            let lastForecast = result.last!
            let next: Decimal
            if let insulinFactor = insulinFactor, dynamicIsfState == .logrithmic {
                let adjustedGlucoseImpact = adjustedGlucoseImpactForLogrithmicDynamicIsf(
                    lastForecast: lastForecast,
                    insulinFactor: insulinFactor,
                    tdd: tdd,
                    adjustmentFactorLogrithmic: adjustmentFactorLogrithmic,
                    iobActivity: iob.activity
                )
                next = lastForecast + adjustedGlucoseImpact + min(0, forecastedDeviation) + forecastedUnannouncedCarbImpact
            } else {
                next = lastForecast + glucoseImpact
                    .jsRounded(scale: 2) + min(0, forecastedDeviation) + forecastedUnannouncedCarbImpact
            }

            if result.count < 48 { result.append(next) }
            if next < minGuardGlucose { minGuardGlucose = next.jsRounded() }
            rawResult.append(next)
        }

        let clampedResult = result.map { $0.clamp(lowerBound: 39, upperBound: 401) }

        return IndividualForecast(
            forecasts: ForecastGenerator.trimFlatTails(clampedResult, lookback: 13),
            minGuardGlucose: minGuardGlucose,
            rawForecasts: rawResult,
            duration: uamDuration.jsRounded(scale: 1)
        )
    }

    static func forecastZT(
        startingGlucose: Decimal,
        glucoseImpactSeriesWithZeroTemp: [Decimal],
        targetBG: Decimal,
        iobData: [IobResult],
        dynamicIsfState: DynamicIsfState,
        insulinFactor: Decimal?,
        tdd: Decimal,
        adjustmentFactorLogrithmic: Decimal
    ) -> IndividualForecast {
        var result = [startingGlucose]
        var rawResult = [startingGlucose]

        var minGuardGlucose = Decimal(999)
        for (glucoseImpact, iob) in zip(glucoseImpactSeriesWithZeroTemp, iobData) {
            let lastForecast = result.last!
            let next: Decimal
            if let insulinFactor = insulinFactor, dynamicIsfState == .logrithmic {
                let adjustedGlucoseImpact = adjustedGlucoseImpactForLogrithmicDynamicIsf(
                    lastForecast: lastForecast,
                    insulinFactor: insulinFactor,
                    tdd: tdd,
                    adjustmentFactorLogrithmic: adjustmentFactorLogrithmic,
                    iobActivity: iob.iobWithZeroTemp.activity
                )
                next = lastForecast + adjustedGlucoseImpact
            } else {
                next = lastForecast + glucoseImpact.jsRounded(scale: 2)
            }

            if result.count < 48 { result.append(next) }
            if next < minGuardGlucose { minGuardGlucose = next.jsRounded() }
            rawResult.append(next)
        }
        let clampedResult = result.map { $0.clamp(lowerBound: 39, upperBound: 401) }
        return IndividualForecast(
            forecasts: ForecastGenerator.trimZTTails(series: clampedResult, targetBG: targetBG),
            minGuardGlucose: minGuardGlucose,
            rawForecasts: rawResult,
            duration: nil
        )
    }

    static func adjustedGlucoseImpactForLogrithmicDynamicIsf(
        lastForecast: Decimal,
        insulinFactor: Decimal,
        tdd: Decimal,
        adjustmentFactorLogrithmic: Decimal,
        iobActivity: Decimal
    ) -> Decimal {
        let adjustedLastForecast = max(lastForecast, 39) / insulinFactor
        let adjustedTdd = tdd * adjustmentFactorLogrithmic * Decimal.log(adjustedLastForecast + 1)
        return (-iobActivity * (1800 / adjustedTdd) * 5).jsRounded(scale: 2)
    }
}
