import Foundation
import OrefSwiftModels

public enum Carbs {
    public static func carbRatioLookup(carbRatio: CarbRatios, now: Date) -> Decimal? {
        guard let lastSchedule = carbRatio.schedule.last else { return nil }
        var currentRatio = lastSchedule.ratio

        do {
            for (curr, next) in zip(carbRatio.schedule, carbRatio.schedule.dropFirst()) {
                if try now.isMinutesFromMidnightWithinRange(lowerBound: curr.offset, upperBound: next.offset) {
                    currentRatio = curr.ratio
                    break
                }
            }
        } catch {
            return nil
        }

        if currentRatio < 3 || currentRatio > 150 {
            return nil
        }

        switch carbRatio.units {
        case .exchanges:
            return 12 / currentRatio
        case .grams:
            return currentRatio
        }
    }
}
