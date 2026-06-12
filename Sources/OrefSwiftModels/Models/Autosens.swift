import Foundation

public struct Autosens: JSON {
    public struct DebugInfo: Codable {
        public let iobClock: Date
        public let bgi: Decimal
        public let iobActivity: Decimal
        public let deltaGlucose: Decimal
        public let deviation: Decimal
        public let stateType: String
        public var mealCOB: Decimal?
        public var absorbing: Bool?
        public var mealCarbs: Decimal?
        public var mealStartCounter: Int?

        public init(
            iobClock: Date,
            bgi: Decimal,
            iobActivity: Decimal,
            deltaGlucose: Decimal,
            deviation: Decimal,
            stateType: String,
            mealCOB: Decimal? = nil,
            absorbing: Bool? = nil,
            mealCarbs: Decimal? = nil,
            mealStartCounter: Int? = nil
        ) {
            self.iobClock = iobClock
            self.bgi = bgi
            self.iobActivity = iobActivity
            self.deltaGlucose = deltaGlucose
            self.deviation = deviation
            self.stateType = stateType
            self.mealCOB = mealCOB
            self.absorbing = absorbing
            self.mealCarbs = mealCarbs
            self.mealStartCounter = mealStartCounter
        }
    }

    public let ratio: Decimal
    public let newisf: Decimal?
    public var deviationsUnsorted: [Decimal]?
    public var timestamp: Date?
    public var debugInfo: [DebugInfo]?
    public var error: String?

    public init(
        ratio: Decimal,
        newisf: Decimal? = nil,
        deviationsUnsorted: [Decimal]? = nil,
        timestamp: Date? = nil,
        debugInfo: [DebugInfo]? = nil,
        error: String? = nil
    ) {
        self.ratio = ratio
        self.newisf = newisf
        self.deviationsUnsorted = deviationsUnsorted
        self.timestamp = timestamp
        self.debugInfo = debugInfo
        self.error = error
    }
}
