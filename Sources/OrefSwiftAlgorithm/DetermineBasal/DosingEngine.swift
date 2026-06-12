import Foundation
import OrefSwiftModels

public enum DosingEngine {
    public struct DosingInputs {
        public let reason: String
        public let carbsRequired: (carbs: Decimal, minutes: Decimal)?
        public let rawCarbsRequired: Decimal
    }

    /// struct to keep the relevant state needed for the output of the SMB decision logic
    public struct SMBDecision {
        public let isEnabled: Bool
        public let minGuardGlucose: Decimal?
        public let reason: String?
    }

    /// checks to see if SMB are enabled via the profile
    private static func isProfileSmbEnabled(
        currentGlucose: Decimal,
        adjustedTargetGlucose: Decimal,
        profile: Profile,
        meal: ComputedCarbs,
        trioCustomOrefVariables: TrioCustomOrefVariables,
        clock: Date
    ) throws -> Bool {
        if trioCustomOrefVariables.smbIsOff {
            return false
        }

        if try isSmbScheduledOff(trioCustomOrefVariables: trioCustomOrefVariables, clock: clock) {
            return false
        }

        if !profile.allowSMBWithHighTemptarget, profile.temptargetSet == true, adjustedTargetGlucose > 100 {
            return false
        }

        if profile.enableSMBAlways {
            return true
        }

        if profile.enableSMBWithCOB, meal.mealCOB > 0 {
            return true
        }

        if profile.enableSMBAfterCarbs, meal.carbs > 0 {
            return true
        }

        if profile.enableSMBWithTemptarget, profile.temptargetSet == true, adjustedTargetGlucose < 100 {
            return true
        }

        if profile.enableSMBHighBg, currentGlucose >= profile.enableSMBHighBgTarget {
            return true
        }

        return false
    }

    /// helper function to check if SMB is scheduled off given the current timezone
    private static func isSmbScheduledOff(trioCustomOrefVariables: TrioCustomOrefVariables, clock: Date) throws -> Bool {
        guard trioCustomOrefVariables.smbIsScheduledOff else {
            return false
        }

        guard let currentHour = clock.hourInLocalTime.map({ Decimal($0) }) else {
            throw CalendarError.invalidCalendarHourOnly
        }
        let startHour = trioCustomOrefVariables.start
        let endHour = trioCustomOrefVariables.end

        // SMBs will be disabled from [start, end) local time
        if startHour < endHour, currentHour >= startHour && currentHour < endHour {
            return true
        } else if startHour > endHour, currentHour >= startHour || currentHour < endHour {
            return true
        } else if startHour == 0, endHour == 0 {
            return true
        } else if startHour == endHour, currentHour == startHour {
            return true
        }

        return false
    }

    /// helper function for reason string glucose output
    public static func convertGlucose(profile: Profile, glucose: Decimal) -> Decimal {
        let units = profile.outUnits ?? .mgdL
        switch units {
        case .mgdL: return glucose.jsRounded()
        case .mmolL: return glucose.asMmolL
        }
    }

    /// Top level smb enabling logic
    public static func makeSMBDosingDecision(
        profile: Profile,
        meal: ComputedCarbs,
        currentGlucose: Decimal,
        adjustedTargetGlucose: Decimal,
        minGuardGlucose: Decimal,
        threshold: Decimal,
        glucoseStatus: GlucoseStatus,
        trioCustomOrefVariables: TrioCustomOrefVariables,
        clock: Date
    ) throws -> SMBDecision {
        var smbIsEnabled = try isProfileSmbEnabled(
            currentGlucose: currentGlucose,
            adjustedTargetGlucose: adjustedTargetGlucose,
            profile: profile,
            meal: meal,
            trioCustomOrefVariables: trioCustomOrefVariables,
            clock: clock
        )

        var minGuardGlucoseDecision: Decimal?
        var reason: String?
        if smbIsEnabled, minGuardGlucose < threshold {
            minGuardGlucoseDecision = minGuardGlucose
            smbIsEnabled = false
        }

        let maxDeltaGlucoseThreshold = min(profile.maxDeltaBgThreshold, 0.4)
        if glucoseStatus.maxDelta > maxDeltaGlucoseThreshold * currentGlucose {
            reason =
                "maxDelta \(convertGlucose(profile: profile, glucose: glucoseStatus.maxDelta)) > \(100 * maxDeltaGlucoseThreshold)% of BG \(convertGlucose(profile: profile, glucose: currentGlucose)) - SMB disabled!, "
            smbIsEnabled = false
        }

        return SMBDecision(
            isEnabled: smbIsEnabled,
            minGuardGlucose: minGuardGlucoseDecision,
            reason: reason
        )
    }

    public static func prepareDosingInputs(
        profile: Profile,
        mealData: ComputedCarbs,
        forecast: ForecastResult,
        naiveEventualGlucose: Decimal,
        threshold: Decimal,
        glucoseImpact: Decimal,
        deviation: Decimal,
        currentBasal: Decimal,
        overrideFactor: Decimal,
        adjustedSensitivity: Decimal,
        isfReason: String,
        tddReason: String,
        targetLog: String
    ) -> DosingInputs {
        let lastIOBpredBG = (forecast.iob.last ?? 0).jsRounded()
        let lastCOBpredBG = forecast.cob?.last?.jsRounded()
        let lastUAMpredBG = forecast.uam?.last?.jsRounded()

        var reason =
            "\(isfReason), COB: \(mealData.mealCOB), Dev: \(deviation.jsRounded()), BGI: \(glucoseImpact.jsRounded()), CR: \(forecast.adjustedCarbRatio.jsRounded(scale: 1)), Target: \(targetLog), minPredBG \(forecast.minForecastedGlucose.jsRounded()), minGuardBG \(forecast.minGuardGlucose.jsRounded()), IOBpredBG \(lastIOBpredBG)"

        if let lastCOB = lastCOBpredBG {
            reason += ", COBpredBG \(lastCOB)"
        }
        if let lastUAM = lastUAMpredBG {
            reason += ", UAMpredBG \(lastUAM)"
        }
        reason += tddReason
        reason += "; " // Start of conclusion

        let carbsRequiredResult = calculateCarbsRequired(
            mealData: mealData,
            naiveEventualGlucose: naiveEventualGlucose,
            minGuardGlucose: forecast.minGuardGlucose,
            threshold: threshold,
            iobForecast: forecast.iob,
            cobForecast: forecast.internalCob,
            carbImpact: forecast.carbImpact,
            remainingCarbImpactPeak: forecast.remainingCarbImpactPeak,
            currentBasal: currentBasal,
            overrideFactor: overrideFactor,
            adjustedSensitivity: adjustedSensitivity,
            adjustedCarbRatio: forecast.adjustedCarbRatio
        )

        var carbsRequired: (carbs: Decimal, minutes: Decimal)?
        if carbsRequiredResult.carbs >= profile.carbsReqThreshold, carbsRequiredResult.minutes <= 45 {
            carbsRequired = carbsRequiredResult
        }

        return DosingInputs(reason: reason, carbsRequired: carbsRequired, rawCarbsRequired: carbsRequiredResult.carbs)
    }

    /// Calculates the carbohydrates required to avoid a potential hypoglycemic event.
    public static func calculateCarbsRequired(
        mealData: ComputedCarbs,
        naiveEventualGlucose: Decimal,
        minGuardGlucose: Decimal,
        threshold: Decimal,
        iobForecast: [Decimal],
        cobForecast: [Decimal],
        carbImpact: Decimal,
        remainingCarbImpactPeak: Decimal,
        currentBasal: Decimal,
        overrideFactor: Decimal,
        adjustedSensitivity: Decimal,
        adjustedCarbRatio: Decimal
    ) -> (carbs: Decimal, minutes: Decimal) {
        var carbsRequiredGlucose = naiveEventualGlucose
        if naiveEventualGlucose < 40 {
            carbsRequiredGlucose = min(minGuardGlucose, naiveEventualGlucose)
        }

        let glucoseUndershoot = threshold - carbsRequiredGlucose

        var minutesAboveThreshold = Decimal(240)

        let useCOBForecast = mealData.mealCOB > 0 && (carbImpact > 0 || remainingCarbImpactPeak > 0)
        let forecast = useCOBForecast ? cobForecast : iobForecast

        for (index, glucose) in forecast.map({ $0.jsRounded() }).enumerated() {
            if glucose < threshold {
                minutesAboveThreshold = Decimal(5) * Decimal(index)
                break
            }
        }

        let zeroTempDuration = minutesAboveThreshold
        let zeroTempEffect = currentBasal * adjustedSensitivity * overrideFactor * zeroTempDuration / 60

        let mealCarbs = mealData.carbs
        let cobForCarbsRequired = max(0, mealData.mealCOB - (Decimal(0.25) * mealCarbs))

        guard adjustedCarbRatio > 0 else { return (carbs: 0, minutes: minutesAboveThreshold) }
        let carbSensitivityFactor = adjustedSensitivity / adjustedCarbRatio
        guard carbSensitivityFactor > 0 else { return (carbs: 0, minutes: minutesAboveThreshold) }

        var carbsRequired = (glucoseUndershoot - zeroTempEffect) / carbSensitivityFactor - cobForCarbsRequired
        carbsRequired = carbsRequired.jsRounded()

        return (carbs: carbsRequired, minutes: minutesAboveThreshold)
    }

    /// Determines if a low glucose suspend is warranted.
    public static func lowGlucoseSuspend(
        currentGlucose: Decimal,
        minGuardGlucose: Decimal,
        iob: Decimal,
        minDelta: Decimal,
        expectedDelta: Decimal,
        threshold: Decimal,
        overrideFactor: Decimal,
        profile: Profile,
        adjustedSensitivity: Decimal,
        targetGlucose: Decimal,
        currentTemp: TempBasal,
        determination: Determination
    ) throws -> (shouldSetTempBasal: Bool, determination: Determination) {
        var newDetermination = determination

        guard let currentBasal = profile.currentBasal else {
            throw TempBasalFunctionError.invalidBasalRateOnProfile
        }

        let suspendThreshold = -currentBasal * overrideFactor * 20 / 60
        if currentGlucose < threshold, iob < suspendThreshold, minDelta > 0, minDelta > expectedDelta {
            let iobString = String(describing: iob)
            let suspendString = String(describing: suspendThreshold.jsRounded(scale: 2))
            let minDeltaString = String(describing: convertGlucose(profile: profile, glucose: minDelta))
            let expectedDeltaString = String(describing: convertGlucose(profile: profile, glucose: expectedDelta))

            newDetermination
                .reason +=
                "IOB \(iobString) < \(suspendString) and minDelta \(minDeltaString) > expectedDelta \(expectedDeltaString); "
            return (shouldSetTempBasal: false, determination: newDetermination)
        } else if currentGlucose < threshold || minGuardGlucose < threshold {
            let minGuardGlucoseString = String(describing: convertGlucose(profile: profile, glucose: minGuardGlucose))
            let thresholdString = String(describing: convertGlucose(profile: profile, glucose: threshold))
            newDetermination.reason += "minGuardBG \(minGuardGlucoseString)<\(thresholdString)"

            let glucoseUndershoot = targetGlucose - minGuardGlucose
            if minGuardGlucose < threshold {
                newDetermination.minGuardBG = minGuardGlucose
            }

            let worstCaseInsulinRequired = glucoseUndershoot / adjustedSensitivity
            var durationRequired = (60 * worstCaseInsulinRequired / currentBasal * overrideFactor).jsRounded()
            durationRequired = (durationRequired / 30).jsRounded() * 30
            durationRequired = max(30, min(120, durationRequired))

            let finalDetermination = try TempBasalFunctions.setTempBasal(
                rate: 0,
                duration: durationRequired,
                profile: profile,
                determination: newDetermination,
                currentTemp: currentTemp
            )
            return (shouldSetTempBasal: true, determination: finalDetermination)
        }

        return (shouldSetTempBasal: false, determination: determination)
    }

    /// Determines if a neutral temp basal should be skipped to avoid pump alerts.
    public static func skipNeutralTempBasal(
        smbIsEnabled: Bool,
        profile: Profile,
        clock: Date,
        currentTemp: TempBasal,
        determination: Determination
    ) throws -> (shouldSetTempBasal: Bool, determination: Determination) {
        guard profile.skipNeutralTemps else {
            return (shouldSetTempBasal: false, determination: determination)
        }
        guard let totalMinutes = clock.minutesSinceMidnight else {
            throw CalendarError.invalidCalendar
        }

        let minute = totalMinutes % 60
        guard minute >= 55 else {
            return (shouldSetTempBasal: false, determination: determination)
        }

        if !smbIsEnabled {
            var newDetermination = determination
            let minutesLeft = 60 - minute
            newDetermination
                .reason +=
                "; Canceling temp at \(minutesLeft)min before turn of the hour to avoid beeping of MDT. SMB are disabled anyways."

            let finalDetermination = try TempBasalFunctions.setTempBasal(
                rate: 0,
                duration: 0,
                profile: profile,
                determination: newDetermination,
                currentTemp: currentTemp
            )
            return (shouldSetTempBasal: true, determination: finalDetermination)
        } else {
            return (shouldSetTempBasal: false, determination: determination)
        }
    }

    /// Handles the case where eventual glucose is predicted to be low.
    public static func handleLowEventualGlucose(
        eventualGlucose: Decimal,
        minGlucose: Decimal,
        targetGlucose: Decimal,
        minDelta: Decimal,
        expectedDelta: Decimal,
        carbsRequired: Decimal,
        naiveEventualGlucose: Decimal,
        glucoseStatus: GlucoseStatus,
        currentTemp: TempBasal,
        basal: Decimal,
        profile: Profile,
        determination: Determination,
        adjustedSensitivity: Decimal,
        overrideFactor: Decimal
    ) throws -> (shouldSetTempBasal: Bool, determination: Determination) {
        guard eventualGlucose < minGlucose else {
            return (shouldSetTempBasal: false, determination: determination)
        }

        var newDetermination = determination
        newDetermination
            .reason +=
            "Eventual BG \(convertGlucose(profile: profile, glucose: eventualGlucose)) < \(convertGlucose(profile: profile, glucose: minGlucose))"

        if minDelta > expectedDelta, minDelta > 0, carbsRequired == 0 {
            if naiveEventualGlucose < 40 {
                newDetermination.reason += ", naive_eventualBG < 40. "
                let finalDetermination = try TempBasalFunctions.setTempBasal(
                    rate: 0,
                    duration: 30,
                    profile: profile,
                    determination: newDetermination,
                    currentTemp: currentTemp
                )
                return (shouldSetTempBasal: true, determination: finalDetermination)
            }

            if glucoseStatus.delta > minDelta {
                newDetermination
                    .reason +=
                    ", but Delta \(convertGlucose(profile: profile, glucose: glucoseStatus.delta)) > expectedDelta \(convertGlucose(profile: profile, glucose: expectedDelta))"
            } else {
                let minDeltaFormatted = String(format: "%.2f", Double(truncating: minDelta.jsRounded(scale: 2) as NSNumber))
                newDetermination
                    .reason +=
                    ", but Min. Delta \(minDeltaFormatted) > Exp. Delta \(convertGlucose(profile: profile, glucose: expectedDelta))"
            }

            let roundedBasal = TempBasalFunctions.roundBasal(profile: profile, basalRate: basal)
            let roundedCurrentRate = TempBasalFunctions.roundBasal(profile: profile, basalRate: currentTemp.rate)

            if currentTemp.duration > 15, roundedBasal == roundedCurrentRate {
                newDetermination.reason += ", temp \(currentTemp.rate) ~ req \(basal)U/hr. "
                return (shouldSetTempBasal: true, determination: newDetermination)
            } else {
                newDetermination.reason += "; setting current basal of \(basal) as temp. "
                let finalDetermination = try TempBasalFunctions.setTempBasal(
                    rate: basal,
                    duration: 30,
                    profile: profile,
                    determination: newDetermination,
                    currentTemp: currentTemp
                )
                return (shouldSetTempBasal: true, determination: finalDetermination)
            }
        }

        // calculate 30m low-temp required to get projected glucose up to target
        var insulinRequired = 2 * min(0, (eventualGlucose - targetGlucose) / adjustedSensitivity)
        insulinRequired = insulinRequired.jsRounded(scale: 2)

        let naiveInsulinRequired = min(0, (naiveEventualGlucose - targetGlucose) / adjustedSensitivity).jsRounded(scale: 2)

        if minDelta < 0, minDelta > expectedDelta {
            let newInsulinRequired = (insulinRequired * (minDelta / expectedDelta)).jsRounded(scale: 2)
            insulinRequired = newInsulinRequired
        }

        var rate = basal + (2 * insulinRequired)
        rate = TempBasalFunctions.roundBasal(profile: profile, basalRate: rate)

        let insulinScheduled = Decimal(currentTemp.duration) * (currentTemp.rate - basal) / 60
        let minInsulinRequired = min(insulinRequired, naiveInsulinRequired)

        if insulinScheduled < minInsulinRequired - basal * 0.3 {
            let rateFormatted = String(format: "%.2f", Double(truncating: currentTemp.rate.jsRounded(scale: 2) as NSNumber))
            newDetermination
                .reason += ", \(currentTemp.duration)m@\(rateFormatted) is a lot less than needed. "
            let finalDetermination = try TempBasalFunctions.setTempBasal(
                rate: rate,
                duration: 30,
                profile: profile,
                determination: newDetermination,
                currentTemp: currentTemp
            )
            return (shouldSetTempBasal: true, determination: finalDetermination)
        }

        if currentTemp.duration > 5, rate >= currentTemp.rate * 0.8 {
            newDetermination.reason += ", temp \(currentTemp.rate) ~< req \(rate)U/hr. "
            return (shouldSetTempBasal: true, determination: newDetermination)
        } else {
            if rate <= 0 {
                guard let currentBasal = profile.currentBasal else {
                    throw TempBasalFunctionError.invalidBasalRateOnProfile
                }
                let glucoseUndershoot = targetGlucose - naiveEventualGlucose
                let worstCaseInsulinRequired = glucoseUndershoot / adjustedSensitivity
                var durationRequired = (60 * worstCaseInsulinRequired / currentBasal * overrideFactor).jsRounded()

                if durationRequired < 0 {
                    durationRequired = 0
                } else {
                    durationRequired = (durationRequired / 30).jsRounded() * 30
                    durationRequired = min(120, max(0, durationRequired))
                }

                if durationRequired > 0 {
                    newDetermination.reason += ", setting \(durationRequired)m zero temp. "
                    let finalDetermination = try TempBasalFunctions.setTempBasal(
                        rate: rate,
                        duration: durationRequired,
                        profile: profile,
                        determination: newDetermination,
                        currentTemp: currentTemp
                    )
                    return (shouldSetTempBasal: true, determination: finalDetermination)
                }
            } else {
                newDetermination.reason += ", setting \(rate)U/hr. "
            }

            let finalDetermination = try TempBasalFunctions.setTempBasal(
                rate: rate,
                duration: 30,
                profile: profile,
                determination: newDetermination,
                currentTemp: currentTemp
            )
            return (shouldSetTempBasal: true, determination: finalDetermination)
        }
    }

    /// Handles the case where glucose is falling faster than expected.
    public static func glucoseFallingFasterThanExpected(
        eventualGlucose: Decimal,
        minGlucose: Decimal,
        minDelta: Decimal,
        expectedDelta: Decimal,
        glucoseStatus: GlucoseStatus,
        currentTemp: TempBasal,
        basal: Decimal,
        smbIsEnabled: Bool,
        profile: Profile,
        determination: Determination
    ) throws -> (shouldSetTempBasal: Bool, determination: Determination) {
        guard minDelta < expectedDelta else {
            return (shouldSetTempBasal: false, determination: determination)
        }

        var newDetermination = determination

        if !smbIsEnabled {
            if glucoseStatus.delta < minDelta {
                newDetermination
                    .reason +=
                    "Eventual BG \(convertGlucose(profile: profile, glucose: eventualGlucose)) > \(convertGlucose(profile: profile, glucose: minGlucose)) but Delta \(convertGlucose(profile: profile, glucose: glucoseStatus.delta)) < Exp. Delta \(convertGlucose(profile: profile, glucose: expectedDelta))"
            } else {
                let minDeltaFormatted = String(format: "%.2f", Double(truncating: minDelta.jsRounded(scale: 2) as NSNumber))
                newDetermination
                    .reason +=
                    "Eventual BG \(convertGlucose(profile: profile, glucose: eventualGlucose)) > \(convertGlucose(profile: profile, glucose: minGlucose)) but Min. Delta \(minDeltaFormatted) < Exp. Delta \(convertGlucose(profile: profile, glucose: expectedDelta))"
            }

            let roundedBasal = TempBasalFunctions.roundBasal(profile: profile, basalRate: basal)
            let roundedCurrentRate = TempBasalFunctions.roundBasal(profile: profile, basalRate: currentTemp.rate)

            if currentTemp.duration > 15, roundedBasal == roundedCurrentRate {
                newDetermination.reason += ", temp \(currentTemp.rate) ~ req \(basal)U/hr. "
                return (shouldSetTempBasal: true, determination: newDetermination)
            } else {
                newDetermination.reason += "; setting current basal of \(basal) as temp. "
                let finalDetermination = try TempBasalFunctions.setTempBasal(
                    rate: basal,
                    duration: 30,
                    profile: profile,
                    determination: newDetermination,
                    currentTemp: currentTemp
                )
                return (shouldSetTempBasal: true, determination: finalDetermination)
            }
        }

        return (shouldSetTempBasal: false, determination: determination)
    }

    /// Handles the case where the eventual or forecasted glucose is less than the max glucose.
    public static func eventualOrForecastGlucoseLessThanMax(
        eventualGlucose: Decimal,
        maxGlucose: Decimal,
        minForecastGlucose: Decimal,
        currentTemp: TempBasal,
        basal: Decimal,
        smbIsEnabled: Bool,
        profile: Profile,
        determination: Determination
    ) throws -> (shouldSetTempBasal: Bool, determination: Determination) {
        guard min(eventualGlucose, minForecastGlucose) < maxGlucose else {
            return (shouldSetTempBasal: false, determination: determination)
        }

        var newDetermination = determination
        newDetermination.minPredBG = minForecastGlucose

        if !smbIsEnabled {
            newDetermination
                .reason +=
                "\(convertGlucose(profile: profile, glucose: eventualGlucose))-\(convertGlucose(profile: profile, glucose: minForecastGlucose)) in range: no temp required"

            let roundedBasal = TempBasalFunctions.roundBasal(profile: profile, basalRate: basal)
            let roundedCurrentRate = TempBasalFunctions.roundBasal(profile: profile, basalRate: currentTemp.rate)

            if currentTemp.duration > 15, roundedBasal == roundedCurrentRate {
                newDetermination.reason += ", temp \(currentTemp.rate) ~ req \(basal)U/hr. "
                return (shouldSetTempBasal: true, determination: newDetermination)
            } else {
                newDetermination.reason += "; setting current basal of \(basal) as temp. "
                let finalDetermination = try TempBasalFunctions.setTempBasal(
                    rate: basal,
                    duration: 30,
                    profile: profile,
                    determination: newDetermination,
                    currentTemp: currentTemp
                )
                return (shouldSetTempBasal: true, determination: finalDetermination)
            }
        }

        return (shouldSetTempBasal: false, determination: determination)
    }

    /// Handles the case where IOB is greater than the max IOB.
    public static func iobGreaterThanMax(
        iob: Decimal,
        maxIob: Decimal,
        currentTemp: TempBasal,
        basal: Decimal,
        profile: Profile,
        determination: Determination
    ) throws -> (shouldSetTempBasal: Bool, determination: Determination) {
        guard iob > maxIob else {
            return (shouldSetTempBasal: false, determination: determination)
        }

        var newDetermination = determination
        newDetermination.reason += "IOB \(iob.jsRounded(scale: 2)) > max_iob \(maxIob)"

        let roundedBasal = TempBasalFunctions.roundBasal(profile: profile, basalRate: basal)
        let roundedCurrentRate = TempBasalFunctions.roundBasal(profile: profile, basalRate: currentTemp.rate)

        if currentTemp.duration > 15, roundedBasal == roundedCurrentRate {
            newDetermination.reason += ", temp \(currentTemp.rate) ~ req \(basal)U/hr. "
            return (shouldSetTempBasal: true, determination: newDetermination)
        } else {
            newDetermination.reason += "; setting current basal of \(basal) as temp. "
            let finalDetermination = try TempBasalFunctions.setTempBasal(
                rate: basal,
                duration: 30,
                profile: profile,
                determination: newDetermination,
                currentTemp: currentTemp
            )
            return (shouldSetTempBasal: true, determination: finalDetermination)
        }
    }

    /// Calculates the insulin required to bring the projected glucose down to the target.
    public static func calculateInsulinRequired(
        minForecastGlucose: Decimal,
        eventualGlucose: Decimal,
        targetGlucose: Decimal,
        adjustedSensitivity: Decimal,
        maxIob: Decimal,
        currentIob: Decimal,
        determination: Determination
    ) -> (insulinRequired: Decimal, determination: Determination) {
        var newDetermination = determination
        var insulinRequired = (
            (min(minForecastGlucose, eventualGlucose) - targetGlucose) / adjustedSensitivity
        ).jsRounded(scale: 2)

        if insulinRequired > maxIob - currentIob {
            newDetermination.reason += "max_iob \(maxIob), "
            insulinRequired = (maxIob - currentIob).jsRounded(scale: 3)
        }
        newDetermination.insulinReq = insulinRequired
        return (insulinRequired, newDetermination)
    }

    /// Determines the maxBolus possible for a Super Micro Bolus (SMB)
    public static func determineMaxBolus(
        currentBasal: Decimal,
        currentIob: Decimal,
        adjustedCarbRatio: Decimal,
        mealData: ComputedCarbs,
        profile: Profile,
        trioCustomOrefVariables: TrioCustomOrefVariables
    ) -> Decimal {
        let mealInsulinRequired = (mealData.mealCOB / adjustedCarbRatio).jsRounded(scale: 3)
        let overrideFactor = trioCustomOrefVariables.overrideFactor()

        var smbMinutesSetting = profile.maxSMBBasalMinutes
        if trioCustomOrefVariables.useOverride, trioCustomOrefVariables.advancedSettings {
            smbMinutesSetting = trioCustomOrefVariables.smbMinutes
        }

        var uamMinutesSetting = profile.maxUAMSMBBasalMinutes
        if trioCustomOrefVariables.useOverride, trioCustomOrefVariables.advancedSettings {
            uamMinutesSetting = trioCustomOrefVariables.uamMinutes
        }

        if currentIob > mealInsulinRequired, currentIob > 0 {
            if uamMinutesSetting > 0 {
                return (currentBasal * overrideFactor * uamMinutesSetting / 60).jsRounded(scale: 1)
            } else {
                return (currentBasal * overrideFactor * 30 / 60).jsRounded(scale: 1)
            }
        } else {
            return (currentBasal * overrideFactor * smbMinutesSetting / 60).jsRounded(scale: 1)
        }
    }

    /// Determines if a Super Micro Bolus (SMB) should be delivered and calculates its size and associated temp basal.
    public static func determineSMBDelivery(
        insulinRequired: Decimal,
        microBolusAllowed: Bool,
        smbIsEnabled: Bool,
        currentGlucose: Decimal,
        threshold: Decimal,
        profile: Profile,
        trioCustomOrefVariables: TrioCustomOrefVariables,
        mealData: ComputedCarbs,
        iobData: [IobResult],
        currentTime: Date,
        targetGlucose: Decimal,
        naiveEventualGlucose: Decimal,
        minIOBForecastedGlucose: Decimal,
        adjustedSensitivity: Decimal,
        adjustedCarbRatio: Decimal,
        basal: Decimal,
        determination: Determination
    ) throws -> (shouldSetTempBasal: Bool, determination: Determination) {
        var newDetermination = determination
        guard microBolusAllowed, smbIsEnabled, currentGlucose > threshold else {
            return (false, newDetermination)
        }

        guard let currentBasal = profile.currentBasal else {
            throw TempBasalFunctionError.invalidBasalRateOnProfile
        }

        guard let currentIob = iobData.first?.iob else {
            return (false, newDetermination)
        }

        let maxBolus = determineMaxBolus(
            currentBasal: currentBasal,
            currentIob: currentIob,
            adjustedCarbRatio: adjustedCarbRatio,
            mealData: mealData,
            profile: profile,
            trioCustomOrefVariables: trioCustomOrefVariables
        )

        let smbDeliveryRatio = min(profile.smbDeliveryRatio, 1)
        let roundSmbTo = 1 / profile.bolusIncrement
        let microBolusWithoutRounding = min(insulinRequired * smbDeliveryRatio, maxBolus)
        let microBolus = (microBolusWithoutRounding * roundSmbTo).floor() / roundSmbTo

        let worstCaseInsulinRequired = (targetGlucose - (naiveEventualGlucose + minIOBForecastedGlucose) / 2) /
            adjustedSensitivity
        var durationRequired = (60 * worstCaseInsulinRequired / currentBasal * trioCustomOrefVariables.overrideFactor())
            .jsRounded()

        // if insulinRequired > 0 but not enough for a microBolus, don't set an SMB zero temp
        if insulinRequired > 0, microBolus < profile.bolusIncrement {
            durationRequired = 0
        }

        var smbLowTempRequired: Decimal = 0
        if durationRequired <= 0 {
            durationRequired = 0
        } else if durationRequired >= 30 {
            durationRequired = (durationRequired / 30).jsRounded() * 30
            durationRequired = min(60, max(0, durationRequired))
        } else {
            // Note: we're using the fully adjusted basal here
            smbLowTempRequired = (basal * durationRequired / 30).jsRounded(scale: 2)
            durationRequired = 30
        }

        newDetermination.reason += " insulinReq \(insulinRequired)"
        if microBolus >= maxBolus {
            newDetermination.reason += "; maxBolus \(maxBolus)"
        }
        if durationRequired > 0 {
            newDetermination.reason += "; setting \(durationRequired)m low temp of \(smbLowTempRequired)U/h"
        }
        newDetermination.reason += ". "

        var smbInterval: Decimal = 3
        if !profile.smbInterval.isNaN {
            smbInterval = min(10, max(1, profile.smbInterval))
        }

        // minutes since last bolus
        let lastBolusAge: Decimal?
        if let lastBolusTime = iobData.first?.lastBolusTime {
            let millisecondsSince1970 = Decimal(currentTime.timeIntervalSince1970 * 1000)
            lastBolusAge = ((millisecondsSince1970 - Decimal(lastBolusTime)) / 60000).jsRounded(scale: 1)
        } else {
            lastBolusAge = nil
        }

        if let lastBolusAge {
            let nextBolusMinutes = (smbInterval - lastBolusAge).jsRounded()
            let nextBolusSeconds = Int(((smbInterval - lastBolusAge) * 60).jsRounded()) % 60

            if lastBolusAge > smbInterval {
                if microBolus > 0 {
                    newDetermination.units = microBolus
                    newDetermination.reason += "Microbolusing \(microBolus)U. "
                }
            } else {
                newDetermination.reason += "Waiting \(nextBolusMinutes)m \(nextBolusSeconds)s to microbolus again. "
            }
        }

        if durationRequired > 0 {
            newDetermination.rate = smbLowTempRequired
            newDetermination.duration = durationRequired
            return (true, newDetermination)
        }

        return (false, newDetermination)
    }

    /// Determines and sets a high temp basal if required to bring glucose down.
    public static func determineHighTempBasal(
        insulinRequired: Decimal,
        basal: Decimal,
        profile: Profile,
        currentTemp: TempBasal,
        determination: Determination
    ) throws -> Determination {
        var newDetermination = determination
        var rate = basal + (2 * insulinRequired)
        rate = TempBasalFunctions.roundBasal(profile: profile, basalRate: rate)

        let maxSafeBasal = try TempBasalFunctions.getMaxSafeBasalRate(profile: profile)

        if rate > maxSafeBasal {
            newDetermination.reason += "adj. req. rate: \(rate) to maxSafeBasal: \(maxSafeBasal.jsRounded(scale: 2)), "
            rate = TempBasalFunctions.roundBasal(profile: profile, basalRate: maxSafeBasal)
        }

        let insulinScheduled = Decimal(currentTemp.duration) * (currentTemp.rate - basal) / 60
        if insulinScheduled >= insulinRequired * 2 {
            let rateFormatted = String(format: "%.2f", Double(truncating: currentTemp.rate.jsRounded(scale: 2) as NSNumber))
            newDetermination.reason +=
                "\(currentTemp.duration)m@\(rateFormatted) > 2 * insulinReq. Setting temp basal of \(rate)U/hr. "
            let finalDetermination = try TempBasalFunctions.setTempBasal(
                rate: rate,
                duration: 30,
                profile: profile,
                determination: newDetermination,
                currentTemp: currentTemp
            )
            return finalDetermination
        }

        if currentTemp.duration == 0 {
            newDetermination.reason += "no temp, setting \(rate)U/hr. "
            let finalDetermination = try TempBasalFunctions.setTempBasal(
                rate: rate,
                duration: 30,
                profile: profile,
                determination: newDetermination,
                currentTemp: currentTemp
            )
            return finalDetermination
        }

        let roundedRate = TempBasalFunctions.roundBasal(profile: profile, basalRate: rate)
        let roundedCurrentRate = TempBasalFunctions.roundBasal(profile: profile, basalRate: currentTemp.rate)

        if currentTemp.duration > 5, roundedRate <= roundedCurrentRate {
            newDetermination.reason += "temp \(currentTemp.rate) >~ req \(rate)U/hr. "
            return newDetermination
        }

        newDetermination.reason += "temp \(currentTemp.rate)<\(rate)U/hr. "
        let finalDetermination = try TempBasalFunctions.setTempBasal(
            rate: rate,
            duration: 30,
            profile: profile,
            determination: newDetermination,
            currentTemp: currentTemp
        )
        return finalDetermination
    }
}
