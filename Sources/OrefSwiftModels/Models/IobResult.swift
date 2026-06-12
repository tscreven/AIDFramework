import Foundation

public struct IobResult: Codable {
    public static func from(iob: IobTotal, iobWithZeroTemp: IobTotal) -> IobResult {
        IobResult(
            iob: iob.iob,
            activity: iob.activity,
            basaliob: iob.basaliob,
            bolusiob: iob.bolusiob,
            netbasalinsulin: iob.netbasalinsulin,
            bolusinsulin: iob.bolusinsulin,
            time: iob.time,
            iobWithZeroTemp: IobWithZeroTemp(
                iob: iobWithZeroTemp.iob,
                activity: iobWithZeroTemp.activity,
                basaliob: iobWithZeroTemp.basaliob,
                bolusiob: iobWithZeroTemp.bolusiob,
                netbasalinsulin: iobWithZeroTemp.netbasalinsulin,
                bolusinsulin: iobWithZeroTemp.bolusinsulin,
                time: iobWithZeroTemp.time
            ),
            lastBolusTime: nil,
            lastTemp: nil
        )
    }

    public let iob: Decimal
    public let activity: Decimal
    public let basaliob: Decimal
    public let bolusiob: Decimal
    public let netbasalinsulin: Decimal
    public let bolusinsulin: Decimal
    public let time: Date
    public let iobWithZeroTemp: IobWithZeroTemp
    public var lastBolusTime: UInt64?
    public var lastTemp: LastTemp?

    public struct IobWithZeroTemp: Codable {
        public let iob: Decimal
        public let activity: Decimal
        public let basaliob: Decimal
        public let bolusiob: Decimal
        public let netbasalinsulin: Decimal
        public let bolusinsulin: Decimal
        public let time: Date

        public init(
            iob: Decimal,
            activity: Decimal,
            basaliob: Decimal,
            bolusiob: Decimal,
            netbasalinsulin: Decimal,
            bolusinsulin: Decimal,
            time: Date
        ) {
            self.iob = iob
            self.activity = activity
            self.basaliob = basaliob
            self.bolusiob = bolusiob
            self.netbasalinsulin = netbasalinsulin
            self.bolusinsulin = bolusinsulin
            self.time = time
        }
    }

    public struct LastTemp: Codable {
        public let rate: Decimal?
        public let timestamp: Date?
        public let started_at: Date?
        public let date: UInt64
        public let duration: Decimal?

        public init(rate: Decimal, timestamp: Date, started_at: Date, date: UInt64, duration: Decimal) {
            self.rate = rate
            self.timestamp = timestamp
            self.started_at = started_at
            self.date = date
            self.duration = duration
        }

        public init() {
            rate = nil
            timestamp = nil
            started_at = nil
            date = 0
            duration = nil
        }
    }

    public init(
        iob: Decimal,
        activity: Decimal,
        basaliob: Decimal,
        bolusiob: Decimal,
        netbasalinsulin: Decimal,
        bolusinsulin: Decimal,
        time: Date,
        iobWithZeroTemp: IobWithZeroTemp,
        lastBolusTime: UInt64?,
        lastTemp: LastTemp?
    ) {
        self.iob = iob
        self.activity = activity
        self.basaliob = basaliob
        self.bolusiob = bolusiob
        self.netbasalinsulin = netbasalinsulin
        self.bolusinsulin = bolusinsulin
        self.time = time
        self.iobWithZeroTemp = iobWithZeroTemp
        self.lastBolusTime = lastBolusTime
        self.lastTemp = lastTemp
    }
}

extension ComputedPumpHistoryEvent {
    public func toLastTemp() -> IobResult.LastTemp? {
        guard let rate = self.rate,
              let duration = self.duration
        else {
            return nil
        }

        return IobResult.LastTemp(
            rate: rate,
            timestamp: timestamp,
            started_at: started_at,
            date: date,
            duration: duration
        )
    }
}
