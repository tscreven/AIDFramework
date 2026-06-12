import Foundation
import OrefSwiftModels

public enum Basal {
    public static func basalLookup(_ basalProfile: [BasalProfileEntry], now: Date) throws -> Decimal? {
        let basalProfileData = basalProfile

        guard let lastBasalRate = basalProfileData.last?.rate, lastBasalRate != 0 else {
            return nil
        }

        for (curr, next) in zip(basalProfileData, basalProfileData.dropFirst()) {
            if try now.isMinutesFromMidnightWithinRange(lowerBound: curr.minutes, upperBound: next.minutes) {
                return curr.rate.rounded(scale: 3)
            }
        }

        return lastBasalRate.rounded(scale: 3)
    }

    public static func maxDailyBasal(_ basalProfile: [BasalProfileEntry]) -> Decimal? {
        guard let maxBasal = basalProfile.map(\.rate).max() else {
            return nil
        }
        return maxBasal
    }
}
