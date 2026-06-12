import Foundation
import OrefSwiftModels

public enum ProfileGenerator {
    public static func generate(
        pumpSettings: PumpSettings,
        bgTargets: BGTargets,
        basalProfile: [BasalProfileEntry],
        isf: InsulinSensitivities,
        preferences: Preferences,
        carbRatios: CarbRatios,
        tempTargets: [TempTarget],
        model: String,
        clock: Date
    ) throws -> Profile {
        let model = model.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !carbRatios.schedule.isEmpty else {
            throw ProfileError.invalidCarbRatio
        }

        var preferences = preferences
        switch (preferences.curve, preferences.useCustomPeakTime) {
        case (.rapidActing, true):
            preferences.insulinPeakTime = max(50, min(preferences.insulinPeakTime, 120))
        case (.rapidActing, false):
            preferences.insulinPeakTime = 75
        case (.ultraRapid, true):
            preferences.insulinPeakTime = max(35, min(preferences.insulinPeakTime, 100))
        case (.ultraRapid, false):
            preferences.insulinPeakTime = 55
        default:
            break
        }

        return try generateProfile(
            pumpSettings: pumpSettings,
            bgTargets: bgTargets,
            basalProfile: basalProfile,
            isf: isf,
            preferences: preferences,
            carbRatios: carbRatios,
            tempTargets: tempTargets,
            model: model,
            clock: clock
        )
    }

    private static func generateProfile(
        pumpSettings: PumpSettings,
        bgTargets: BGTargets,
        basalProfile: [BasalProfileEntry],
        isf: InsulinSensitivities,
        preferences: Preferences,
        carbRatios: CarbRatios,
        tempTargets: [TempTarget],
        model: String,
        clock: Date
    ) throws -> Profile {
        var profile = Profile()

        profile.update(from: preferences)

        guard pumpSettings.insulinActionCurve >= 5 else {
            throw ProfileError.invalidDIA(value: pumpSettings.insulinActionCurve)
        }
        profile.dia = pumpSettings.insulinActionCurve

        profile.model = model
        profile.skipNeutralTemps = preferences.skipNeutralTemps

        profile.currentBasal = try Basal.basalLookup(basalProfile, now: clock)
        profile.basalprofile = basalProfile

        let roundedBasalProfile = basalProfile
            .map { BasalProfileEntry(start: $0.start, minutes: $0.minutes, rate: $0.rate.rounded(scale: 3)) }

        profile.maxDailyBasal = Basal.maxDailyBasal(roundedBasalProfile)
        profile.maxBasal = pumpSettings.maxBasal

        if let currentBasal = profile.currentBasal {
            guard currentBasal != 0 else {
                throw ProfileError.invalidCurrentBasal(value: profile.currentBasal)
            }
        }

        if let maxDailyBasal = profile.maxDailyBasal {
            guard maxDailyBasal != 0 else {
                throw ProfileError.invalidMaxDailyBasal(value: profile.maxDailyBasal)
            }
        }

        if let maxBasal = profile.maxBasal {
            guard maxBasal >= 0.1 else {
                throw ProfileError.invalidMaxBasal(value: profile.maxBasal)
            }
        }

        profile.outUnits = bgTargets.userPreferredUnits
        let (updatedTargets, range) = try Targets
            .bgTargetsLookup(targets: bgTargets, tempTargets: tempTargets, profile: profile, now: clock)
        profile.minBg = range.minBg?.rounded()
        profile.maxBg = range.maxBg?.rounded()

        let roundedTargets = updatedTargets.targets.map { target -> ComputedBGTargetEntry in
            ComputedBGTargetEntry(
                low: target.low.rounded(),
                high: target.high.rounded(),
                start: target.start,
                offset: target.offset,
                maxBg: target.maxBg?.rounded(),
                minBg: target.minBg?.rounded(),
                temptargetSet: target.temptargetSet
            )
        }

        profile.bgTargets = ComputedBGTargets(
            units: updatedTargets.units,
            userPreferredUnits: updatedTargets.userPreferredUnits,
            targets: roundedTargets
        )

        profile.temptargetSet = range.temptargetSet
        let (sens, isfUpdated) = try Isf.isfLookup(isfDataInput: isf, timestamp: clock)
        profile.sens = sens
        profile.isfProfile = isfUpdated

        if let sens = profile.sens {
            guard sens >= 5 else {
                throw ProfileError.invalidISF(value: profile.sens)
            }
        }

        guard let currentCarbRatio = Carbs.carbRatioLookup(carbRatio: carbRatios, now: clock) else {
            throw ProfileError.invalidCarbRatio
        }
        profile.carbRatio = currentCarbRatio
        profile.carbRatios = carbRatios

        return profile
    }
}
