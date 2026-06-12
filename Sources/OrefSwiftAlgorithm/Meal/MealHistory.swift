import Foundation
import OrefSwiftModels

/// Represents the "temp" object built in JS meal/history.js
public struct MealInput {
    public let timestamp: Date
    public var carbs: Decimal? /// `current.carbs`
    public var bolus: Decimal? /// from `current.amount` in Bolus events

    public enum InputType: String {
        case carbs
        case bolus
    }
}

private struct MealInputKey: Hashable {
    let timestamp: Date
    let type: MealInput.InputType
}

public enum MealHistory {
    /// Converts carb and bolus records into a single, chronological list of MealInput,
    /// removing any duplicate entries of the same type whose timestamps are within +/-2 seconds.
    public static func findMealInputs(
        pumpHistory: [PumpHistoryEvent],
        carbHistory: [CarbsEntry]
    ) -> [MealInput] {
        let carbInputs = carbHistory.compactMap { entry -> MealInput? in
            guard entry.carbs > 0 else { return nil }
            return MealInput(
                timestamp: entry.createdAt,
                carbs: entry.carbs,
                bolus: nil
            )
        }

        let bolusInputs = pumpHistory.compactMap { ev -> MealInput? in
            guard ev.type == .bolus, let amt = ev.amount else { return nil }
            return MealInput(
                timestamp: ev.timestamp,
                carbs: nil,
                bolus: amt
            )
        }

        let combinedIputs = carbInputs + bolusInputs
        var seenBuckets: [MealInput.InputType: Set<Int>] = [
            .carbs: Set(),
            .bolus: Set()
        ]

        var dedupedInputs: [MealInput] = []
        dedupedInputs.reserveCapacity(combinedIputs.count)

        for input in combinedIputs {
            let type: MealInput.InputType = input.carbs != nil ? .carbs : .bolus
            let tSec = Int(input.timestamp.timeIntervalSince1970)

            let bucket = seenBuckets[type]!
            let isDuplicate = (tSec - 2 ... tSec + 2).contains { bucket.contains($0) }

            if !isDuplicate {
                dedupedInputs.append(input)

                var newBucket = bucket
                newBucket.insert(tSec)
                seenBuckets[type] = newBucket
            }
        }

        return dedupedInputs
    }
}
