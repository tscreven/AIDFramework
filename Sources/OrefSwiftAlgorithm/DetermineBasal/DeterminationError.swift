import Foundation

public enum DeterminationError: LocalizedError, Equatable {
    case missingGlucoseStatus
    case missingProfile
    case missingCurrentBasal
    case invalidProfileTarget
    case glucoseOutOfRange(glucose: Decimal)
    case cgmNoiseTooHigh(noise: Int)
    case noDelta
    case missingIob
    case missingInputs
    case eventualGlucoseCalculationError(sensitivity: Decimal, deviation: Decimal)
    case determinationError

    public var errorDescription: String? {
        switch self {
        case .missingGlucoseStatus:
            return "No glucose status; cannot determine basal."
        case .missingProfile:
            return "No profile; cannot determine basal."
        case .missingCurrentBasal:
            // string copied from JS
            return "Error: could not get current basal rate"
        case .invalidProfileTarget:
            // string copied from JS including trailing space
            return "Error: could not determine target_bg. "
        case let .glucoseOutOfRange(glucose):
            return "Glucose out of range: \(glucose.description)."
        case let .cgmNoiseTooHigh(noise):
            return "CGM noise level too high: \(noise)."
        case .noDelta:
            return "No glucose delta (flat readings); cannot determine trend."
        case .missingIob:
            return "No IOB data available; cannot determine basal."
        case .missingInputs:
            return "Missing required inputs; cannot determine basal."
        case let .eventualGlucoseCalculationError(sensitivity, deviation):
            return "Could not calculate eventual glucose. Sensitivity: \(sensitivity.description), Deviation: \(deviation.description)"
        case .determinationError:
            return "Unknown determination error."
        }
    }
}
