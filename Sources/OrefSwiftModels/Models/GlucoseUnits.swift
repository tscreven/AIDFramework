import Foundation

public enum GlucoseUnits: String, JSON, Equatable, CaseIterable, Identifiable {
    case mgdL = "mg/dL"
    case mmolL = "mmol/L"

    public static let exchangeRate: Decimal = 0.0555

    public var id: String { rawValue }
}
