import Foundation

public struct BGTargets: JSON {
    public var units: GlucoseUnits
    public var userPreferredUnits: GlucoseUnits
    public var targets: [BGTargetEntry]

    public init(units: GlucoseUnits, userPreferredUnits: GlucoseUnits, targets: [BGTargetEntry]) {
        self.units = units
        self.userPreferredUnits = userPreferredUnits
        self.targets = targets
    }
}

extension BGTargets {
    private enum CodingKeys: String, CodingKey {
        case units
        case userPreferredUnits = "user_preferred_units"
        case targets
    }
}

public struct BGTargetEntry: JSON {
    public let low: Decimal
    public let high: Decimal
    public let start: String
    public let offset: Int

    public init(low: Decimal, high: Decimal, start: String, offset: Int) {
        self.low = low
        self.high = high
        self.start = start
        self.offset = offset
    }
}
