import Foundation
import OrefSwiftModels

public struct AutosensGenerator {
    /// Internal structure to keep track of bucketed glucose values
    struct BucketedGlucose {
        let glucose: Decimal
        let date: Date
    }

    /// Internal structure to keep track of the insulin effects simulation state
    struct SimulationState {
        enum StateType: String {
            case initialState = ""
            case csf
            case uam
            case nonMeal = "non-meal"
        }

        var meals: [MealInput]
        var absorbing = false
        var uam = false
        var mealCOB: Decimal = 0
        var mealCarbs: Decimal = 0
        var mealStartCounter: Int = 999
        var type: StateType = .initialState
    }

    /// Generates autosens ratio by analyzing glucose deviations from expected insulin activity
    public static func generate(
        glucose: [BloodGlucose],
        pumpHistory: [PumpHistoryEvent],
        basalProfile: [BasalProfileEntry],
        profile: Profile,
        carbs: [CarbsEntry],
        tempTargets: [TempTarget],
        maxDeviations: Int,
        clock: Date,
        includeDeviationsForTesting: Bool = false
    ) throws -> Autosens {
        guard glucose.count >= 72 else {
            return Autosens(ratio: 1, newisf: nil, error: "not enough glucose data to calculate autosens")
        }

        let lastSiteChange = determineLastSiteChange(pumpHistory: pumpHistory, profile: profile, clock: clock)

        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory.map { $0.computedEvent() },
            profile: profile,
            clock: clock,
            autosens: nil,
            zeroTempDuration: nil
        )

        let bucketedData = bucketGlucose(glucose: glucose, lastSiteChange: lastSiteChange)

        let meals = findMeals(history: pumpHistory, carbs: carbs, profile: profile, bucketedGlucose: bucketedData)

        var state = SimulationState(meals: meals)
        var deviations: [Decimal] = []
        var debugInfoList: [Autosens.DebugInfo] = []

        for (oldGlucose, (prevGlucose, currGlucose)) in zip(
            bucketedData,
            zip(bucketedData.dropFirst(2), bucketedData.dropFirst(3))
        ) {
            if oldGlucose.glucose < 40 || prevGlucose.glucose < 40 || currGlucose.glucose < 40 {
                continue
            }

            guard let isfProfile = profile.isfProfile?.toInsulinSensitivities() else {
                throw AutosensError.missingIsfProfile
            }
            let (sensitivity, _) = try Isf.isfLookup(isfDataInput: isfProfile, timestamp: currGlucose.date)
            guard sensitivity > 0 else {
                throw AutosensError.isfLookupError
            }
            let deltaGlucose = currGlucose.glucose - prevGlucose.glucose
            var simulationProfile = profile
            simulationProfile.currentBasal = try Basal.basalLookup(basalProfile, now: currGlucose.date)
            simulationProfile.temptargetSet = false
            let iob = try IobCalculation.iobTotal(treatments: treatments, profile: simulationProfile, time: currGlucose.date)

            let bgi = (-iob.activity * sensitivity * 5 * 100 + 0.5).rounded(scale: 0, roundingMode: .down) / 100

            var deviation = deltaGlucose - bgi

            if currGlucose.glucose < 80, deviation > 0 {
                deviation = 0
            }

            state = try advanceSimulationState(
                state: state,
                glucose: currGlucose,
                profile: simulationProfile,
                sensitivity: sensitivity,
                iob: iob.iob,
                deviation: deviation
            )

            debugInfoList.append(Autosens.DebugInfo(
                iobClock: currGlucose.date,
                bgi: bgi,
                iobActivity: iob.activity,
                deltaGlucose: deltaGlucose,
                deviation: deviation,
                stateType: state.type.rawValue,
                mealCOB: state.mealCOB,
                absorbing: state.absorbing,
                mealCarbs: state.mealCarbs,
                mealStartCounter: state.mealStartCounter
            ))

            if state.type == .nonMeal {
                deviations.append(deviation)
            }

            if let tempTargetDeviation = tempTargetDeviation(tempTargets: tempTargets, profile: profile, time: currGlucose.date) {
                deviations.append(tempTargetDeviation)
            }

            if everyOtherHourOnTheHour(glucoseDate: currGlucose.date) {
                deviations.append(0)
            }

            if deviations.count > maxDeviations {
                deviations = deviations.dropFirst().map { $0 }
            }
        }

        if deviations.count < 96 {
            let dataCompleteness = Double(deviations.count) / 96.0
            let paddingNeeded = Int(round((1.0 - dataCompleteness) * 18.0))

            for _ in 0 ..< paddingNeeded {
                deviations.append(0)
            }
        }

        return try statisticsOnDeviations(
            deviations: deviations,
            profile: profile,
            debugInfoList: debugInfoList,
            includeDeviationsForTesting: includeDeviationsForTesting
        )
    }

    /// Calculates deviation adjustment for high temp targets to raise sensitivity
    static func tempTargetDeviation(tempTargets: [TempTarget], profile: Profile, time: Date) -> Decimal? {
        guard profile.highTemptargetRaisesSensitivity else {
            return nil
        }

        guard let tempTarget = tempTargetRunning(tempTargets: tempTargets, time: time), tempTarget > 100 else {
            return nil
        }

        return -(tempTarget - 100) / 20
    }

    /// Calculates autosens ratio and new ISF from glucose deviation statistics
    private static func statisticsOnDeviations(
        deviations: [Decimal],
        profile: Profile,
        debugInfoList: [Autosens.DebugInfo],
        includeDeviationsForTesting: Bool
    ) throws -> Autosens {
        guard let profileSensitivity = profile.sens else {
            throw AutosensError.missingSensInProfile
        }
        guard let maxDailyBasal = profile.maxDailyBasal else {
            throw AutosensError.missingMaxDailyBasalInProfile
        }

        let deviationsUnsorted = deviations
        let deviations = deviations.sorted()

        let medianDeviation = percentile(deviations, 0.50)

        var basalOff: Decimal = 0

        if medianDeviation < 0 {
            basalOff = medianDeviation * (60 / 5) / profileSensitivity
        } else if medianDeviation > 0 {
            basalOff = medianDeviation * (60 / 5) / profileSensitivity
        }

        var ratio = 1 + (basalOff / maxDailyBasal)

        ratio = ratio.clamp(lowerBound: profile.autosensMin, upperBound: profile.autosensMax)

        ratio = ratio.rounded(scale: 2)

        let newISF = (profileSensitivity / ratio).rounded()

        if includeDeviationsForTesting {
            return Autosens(ratio: ratio, newisf: newISF, deviationsUnsorted: deviationsUnsorted, debugInfo: debugInfoList)
        } else {
            return Autosens(ratio: ratio, newisf: newISF)
        }
    }

    /// Calculate percentile of a sorted array - direct port of JS implementation
    private static func percentile(_ sortedArray: [Decimal], _ p: Double) -> Decimal {
        if sortedArray.isEmpty { return 0 }
        if p <= 0 { return sortedArray[0] }
        if p >= 1 { return sortedArray[sortedArray.count - 1] }

        let index = Double(sortedArray.count) * p
        let lower = Int(floor(index))
        let upper = lower + 1
        let weight = index.truncatingRemainder(dividingBy: 1.0)

        if upper >= sortedArray.count { return sortedArray[lower] }

        let weightDecimal = Decimal(weight)
        return sortedArray[lower] * (1 - weightDecimal) + sortedArray[upper] * weightDecimal
    }

    /// Returns true if the time is within first 5 minutes of an even hour based on local timezone
    private static func everyOtherHourOnTheHour(glucoseDate: Date) -> Bool {
        let calendar = Calendar.current
        let minutes = calendar.component(.minute, from: glucoseDate)
        let hours = calendar.component(.hour, from: glucoseDate)

        if minutes >= 0, minutes < 5 {
            if hours % 2 == 0 {
                return true
            }
        }

        return false
    }

    /// Advances simulation state based on carb absorption and IOB levels.
    private static func advanceSimulationState(
        state: SimulationState,
        glucose: BucketedGlucose,
        profile: Profile,
        sensitivity: Decimal,
        iob: Decimal,
        deviation: Decimal
    ) throws -> SimulationState {
        var state = state

        if let meal = state.meals.last, meal.timestamp < glucose.date {
            if let carbs = meal.carbs, carbs >= 1 {
                state.mealCOB += carbs
                state.mealCarbs += carbs
            }
            state.meals = state.meals.dropLast()
        }

        if state.mealCOB > 0 {
            guard let carbRatio = profile.carbRatio else {
                throw AutosensError.missingCarbRatioInProfile
            }
            let ci = max(deviation, profile.min5mCarbImpact)
            let absorbed = ci * carbRatio / sensitivity
            state.mealCOB = max(0, state.mealCOB - absorbed)
        }

        if state.mealCOB > 0 || state.absorbing || state.mealCarbs > 0 {
            state.absorbing = deviation > 0
            if state.mealStartCounter > 60, state.mealCOB < 0.5 {
                state.absorbing = false
            }
            if !state.absorbing, state.mealCOB < 0.5 {
                state.mealCarbs = 0
            }

            if state.type != .csf {
                state.mealStartCounter = 0
            }
            state.mealStartCounter += 1
            state.type = .csf
        } else {
            guard let currentBasal = profile.currentBasal else {
                throw AutosensError.missingCurrentBasalInProfile
            }
            if iob > 2 * currentBasal || state.uam || state.mealStartCounter < 9 {
                state.mealStartCounter += 1
                state.uam = deviation > 0

                state.type = .uam
            } else {
                state.type = .nonMeal
            }
        }

        return state
    }

    /// Finds carbs and returns them in descending order, oldest records first
    private static func findMeals(
        history: [PumpHistoryEvent],
        carbs: [CarbsEntry],
        profile _: Profile,
        bucketedGlucose: [BucketedGlucose]
    ) -> [MealInput] {
        let oldestGlucose = bucketedGlucose.first?.date ?? .distantPast
        let meals = MealHistory.findMealInputs(pumpHistory: history, carbHistory: carbs).filter { $0.timestamp >= oldestGlucose }

        return meals.sorted(by: { $0.timestamp > $1.timestamp })
    }

    /// Find the last site change, falling back to 24 hours ago if not found
    static func determineLastSiteChange(pumpHistory: [PumpHistoryEvent], profile: Profile, clock: Date) -> Date {
        let mostRecentRewind = pumpHistory.dropFirst().first(where: { $0.type == .rewind })
        guard profile.rewindResetsAutosens, let mostRecentRewind = mostRecentRewind else {
            return clock - 24.hoursToSeconds
        }

        return mostRecentRewind.timestamp
    }

    /// Groups glucose readings into time buckets, averaging readings within 2 minutes
    private static func bucketGlucose(glucose: [BloodGlucose], lastSiteChange: Date) -> [BucketedGlucose] {
        let glucoseData = glucose.compactMap({ (bg: BloodGlucose) -> BucketedGlucose? in
            guard let glucose = bg.glucose ?? bg.sgv else { return nil }
            return BucketedGlucose(glucose: Decimal(glucose), date: bg.dateString)
        }).reversed()

        guard let first = glucoseData.first else { return [] }

        var bucketedData = [first]
        var index = 0
        for (previousGlucose, currentGlucose) in zip(glucoseData, glucoseData.dropFirst()) {
            guard previousGlucose.glucose >= 39, currentGlucose.glucose >= 39 else {
                continue
            }

            guard currentGlucose.date >= lastSiteChange else {
                continue
            }

            let elapsedTime = currentGlucose.date.timeIntervalSince(previousGlucose.date).secondsToMinutes
            if abs(elapsedTime) > 2 {
                index += 1
                bucketedData.append(currentGlucose)
            } else {
                let averageGlucose = 0.5 * (bucketedData[index].glucose + currentGlucose.glucose)
                bucketedData[index] = BucketedGlucose(glucose: averageGlucose, date: bucketedData[index].date)
            }
        }

        return bucketedData.dropFirst().map { $0 }
    }

    /// Returns the current active temp target value, or nil if none is active
    private static func tempTargetRunning(tempTargets: [TempTarget], time: Date) -> Decimal? {
        let sortedTargets = tempTargets.sorted { $0.createdAt > $1.createdAt }

        for target in sortedTargets {
            let startTime = target.createdAt
            let durationSeconds = TimeInterval(target.duration * 60)
            let expirationTime = startTime.addingTimeInterval(durationSeconds)

            if time >= startTime, target.duration == 0 {
                return nil
            }

            if time >= startTime, time < expirationTime {
                guard let targetTop = target.targetTop, let targetBottom = target.targetBottom else {
                    return nil
                }
                return (targetTop + targetBottom) / 2
            }
        }

        return nil
    }
}
