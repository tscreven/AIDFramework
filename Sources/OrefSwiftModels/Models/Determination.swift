import Foundation

public struct DeterminationErrorResponse: JSON, Equatable {
    public let error: String

    public init(error: String) {
        self.error = error
    }
}

public struct Determination: JSON, Equatable {
    public let id: UUID?
    public var reason: String
    public var units: Decimal?
    public var insulinReq: Decimal?
    public var eventualBG: Int?
    public let sensitivityRatio: Decimal?
    public var rate: Decimal?
    public var duration: Decimal?
    public let iob: Decimal?
    public let cob: Decimal?
    public var predictions: Predictions?
    public var deliverAt: Date?
    public let carbsReq: Decimal?
    public let temp: TempType?
    public var bg: Decimal?
    public let reservoir: Decimal?
    public var isf: Decimal?
    public var timestamp: Date?

    /// `tdd` (Total Daily Dose) is included so it can be part of the
    /// enacted and suggested devicestatus data that gets uploaded to Nightscout.
    public var tdd: Decimal?

    public var current_target: Decimal?
    public var minDelta: Decimal?
    public var expectedDelta: Decimal?
    public var minGuardBG: Decimal?
    public var minPredBG: Decimal?
    public var threshold: Decimal?
    public let carbRatio: Decimal?
    public let received: Bool?

    public init(
        id: UUID?,
        reason: String,
        units: Decimal?,
        insulinReq: Decimal?,
        eventualBG: Int?,
        sensitivityRatio: Decimal?,
        rate: Decimal?,
        duration: Decimal?,
        iob: Decimal?,
        cob: Decimal?,
        predictions: Predictions?,
        deliverAt: Date?,
        carbsReq: Decimal?,
        temp: TempType?,
        bg: Decimal?,
        reservoir: Decimal?,
        isf: Decimal?,
        timestamp: Date?,
        tdd: Decimal?,
        current_target: Decimal?,
        minDelta: Decimal?,
        expectedDelta: Decimal?,
        minGuardBG: Decimal?,
        minPredBG: Decimal?,
        threshold: Decimal?,
        carbRatio: Decimal?,
        received: Bool?
    ) {
        self.id = id
        self.reason = reason
        self.units = units
        self.insulinReq = insulinReq
        self.eventualBG = eventualBG
        self.sensitivityRatio = sensitivityRatio
        self.rate = rate
        self.duration = duration
        self.iob = iob
        self.cob = cob
        self.predictions = predictions
        self.deliverAt = deliverAt
        self.carbsReq = carbsReq
        self.temp = temp
        self.bg = bg
        self.reservoir = reservoir
        self.isf = isf
        self.timestamp = timestamp
        self.tdd = tdd
        self.current_target = current_target
        self.minDelta = minDelta
        self.expectedDelta = expectedDelta
        self.minGuardBG = minGuardBG
        self.minPredBG = minPredBG
        self.threshold = threshold
        self.carbRatio = carbRatio
        self.received = received
    }
}

public struct Predictions: JSON, Equatable {
    public let iob: [Int]?
    public let zt: [Int]?
    public let cob: [Int]?
    public let uam: [Int]?

    public init(iob: [Int]?, zt: [Int]?, cob: [Int]?, uam: [Int]?) {
        self.iob = iob
        self.zt = zt
        self.cob = cob
        self.uam = uam
    }
}

extension Determination {
    private enum CodingKeys: String, CodingKey {
        case id
        case reason
        case units
        case insulinReq
        case eventualBG
        case sensitivityRatio
        case rate
        case duration
        case iob = "IOB"
        case cob = "COB"
        case predictions = "predBGs"
        case deliverAt
        case carbsReq
        case temp
        case bg
        case reservoir
        case timestamp
        case isf = "ISF"
        case current_target
        case tdd = "TDD"
        case minDelta
        case expectedDelta
        case minGuardBG
        case minPredBG
        case threshold
        case carbRatio = "CR"
        case received
    }
}

extension Predictions {
    private enum CodingKeys: String, CodingKey {
        case iob = "IOB"
        case zt = "ZT"
        case cob = "COB"
        case uam = "UAM"
    }
}
