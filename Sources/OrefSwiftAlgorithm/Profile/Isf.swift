import Foundation
import OrefSwiftModels

public enum Isf {
    public static func isfLookup(
        isfDataInput: InsulinSensitivities,
        timestamp: Date
    ) throws -> (Decimal, ComputedInsulinSensitivities) {
        let now = timestamp
        let isfData = isfDataInput.computedInsulinSensitivies()

        let sortedSensitivities = isfData.sensitivities.sorted { $0.offset < $1.offset }

        guard let firstSensitivity = sortedSensitivities.first,
              firstSensitivity.offset == 0
        else {
            return (-1, isfData)
        }

        guard var isfSchedule = sortedSensitivities.last else {
            return (-1, isfData)
        }

        var endMinutes = 1440

        for (curr, next) in zip(sortedSensitivities, sortedSensitivities.dropFirst()) {
            if try now.isMinutesFromMidnightWithinRange(lowerBound: curr.offset, upperBound: next.offset) {
                endMinutes = next.offset
                isfSchedule = curr
                break
            }
        }

        let updatedSchedule = isfData.sensitivities.map { sensitivity in
            if sensitivity.id == isfSchedule.id {
                return ComputedInsulinSensitivityEntry(
                    sensitivity: sensitivity.sensitivity,
                    offset: sensitivity.offset,
                    start: sensitivity.start,
                    endOffset: endMinutes,
                    id: sensitivity.id
                )
            } else {
                return sensitivity
            }
        }

        return (
            isfSchedule.sensitivity,
            ComputedInsulinSensitivities(
                units: isfData.units,
                userPreferredUnits: isfData.userPreferredUnits,
                sensitivities: updatedSchedule
            )
        )
    }
}
