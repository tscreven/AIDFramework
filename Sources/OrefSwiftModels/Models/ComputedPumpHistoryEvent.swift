import Foundation

public struct ComputedPumpHistoryEvent: Codable, Equatable, Identifiable {
    public let id: String
    public let type: EventType
    public let timestamp: Date
    public let amount: Decimal?
    public var duration: Decimal?
    public let durationMin: Int?
    public let rate: Decimal?
    public let temp: TempType?
    public let carbInput: Int?
    public let fatInput: Int?
    public let proteinInput: Int?
    public let note: String?
    public let isSMB: Bool?
    public let isExternal: Bool?
    public let insulin: Decimal?
    public let isTempBolus: Bool
    public let omitFromTempHistory: Bool

    public let started_at: Date
    public let date: UInt64

    public var end: Date {
        timestamp + (duration ?? durationMin.map { Decimal($0) } ?? 0).minutesToSeconds
    }

    public init(
        id: String,
        type: EventType,
        timestamp: Date,
        amount: Decimal?,
        duration: Decimal?,
        durationMin: Int?,
        rate: Decimal?,
        temp: TempType?,
        carbInput: Int?,
        fatInput: Int?,
        proteinInput: Int?,
        note: String?,
        isSMB: Bool?,
        isExternal: Bool?,
        insulin: Decimal?,
        isTempBolus: Bool = false,
        omitFromTempHistory: Bool = false
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.amount = amount
        self.duration = duration
        self.durationMin = durationMin
        self.rate = rate
        self.temp = temp
        self.carbInput = carbInput
        self.fatInput = fatInput
        self.proteinInput = proteinInput
        self.note = note
        self.isSMB = isSMB
        self.isExternal = isExternal
        self.insulin = insulin
        self.isTempBolus = isTempBolus
        self.omitFromTempHistory = omitFromTempHistory

        started_at = timestamp
        date = UInt64(timestamp.timeIntervalSince1970 * 1000)
    }
}

extension ComputedPumpHistoryEvent {
    private enum CodingKeys: String, CodingKey {
        case id
        case type = "_type"
        case timestamp
        case amount
        case duration
        case durationMin = "duration (min)"
        case rate
        case temp
        case carbInput = "carb_input"
        case fatInput
        case proteinInput
        case note
        case isSMB
        case isExternal
        case started_at
        case date
        case insulin
        case isTempBolus
        case omitFromTempHistory
    }
}

extension PumpHistoryEvent {
    public func computedEvent() -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: id,
            type: type,
            timestamp: timestamp,
            amount: amount,
            duration: duration.map { Decimal($0) },
            durationMin: durationMin,
            rate: rate,
            temp: temp,
            carbInput: carbInput,
            fatInput: fatInput,
            proteinInput: proteinInput,
            note: note,
            isSMB: isSMB,
            isExternal: isExternal,
            insulin: nil
        )
    }
}

extension ComputedPumpHistoryEvent {
    public func copyWith(duration: Decimal?) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: id,
            type: type,
            timestamp: timestamp,
            amount: amount,
            duration: duration,
            durationMin: durationMin,
            rate: rate,
            temp: temp,
            carbInput: carbInput,
            fatInput: fatInput,
            proteinInput: proteinInput,
            note: note,
            isSMB: isSMB,
            isExternal: isExternal,
            insulin: insulin,
            omitFromTempHistory: omitFromTempHistory
        )
    }

    public func copyWith(duration: Decimal, timestamp: Date) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: id,
            type: type,
            timestamp: timestamp,
            amount: amount,
            duration: duration,
            durationMin: durationMin,
            rate: rate,
            temp: temp,
            carbInput: carbInput,
            fatInput: fatInput,
            proteinInput: proteinInput,
            note: note,
            isSMB: isSMB,
            isExternal: isExternal,
            insulin: insulin,
            omitFromTempHistory: omitFromTempHistory
        )
    }

    public func copyWith(duration: Decimal, timestamp: Date, omitFromTempHistory: Bool) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: id,
            type: type,
            timestamp: timestamp,
            amount: amount,
            duration: duration,
            durationMin: durationMin,
            rate: rate,
            temp: temp,
            carbInput: carbInput,
            fatInput: fatInput,
            proteinInput: proteinInput,
            note: note,
            isSMB: isSMB,
            isExternal: isExternal,
            insulin: insulin,
            omitFromTempHistory: omitFromTempHistory
        )
    }

    public func copyWith(insulin: Decimal?) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: id,
            type: type,
            timestamp: timestamp,
            amount: amount,
            duration: duration,
            durationMin: durationMin,
            rate: rate,
            temp: temp,
            carbInput: carbInput,
            fatInput: fatInput,
            proteinInput: proteinInput,
            note: note,
            isSMB: isSMB,
            isExternal: isExternal,
            insulin: insulin,
            omitFromTempHistory: omitFromTempHistory
        )
    }

    public static func zeroTempBasal(timestamp: Date, duration: Decimal, omitFromTempHistory: Bool) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: UUID().uuidString,
            type: .tempBasal,
            timestamp: timestamp,
            amount: nil,
            duration: duration,
            durationMin: nil,
            rate: 0,
            temp: nil,
            carbInput: nil,
            fatInput: nil,
            proteinInput: nil,
            note: nil,
            isSMB: nil,
            isExternal: nil,
            insulin: nil,
            omitFromTempHistory: omitFromTempHistory
        )
    }

    public static func tempBolus(timestamp: Date, insulin: Decimal) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: UUID().uuidString,
            type: .bolus,
            timestamp: timestamp,
            amount: nil,
            duration: nil,
            durationMin: nil,
            rate: nil,
            temp: nil,
            carbInput: nil,
            fatInput: nil,
            proteinInput: nil,
            note: nil,
            isSMB: nil,
            isExternal: nil,
            insulin: insulin,
            isTempBolus: true
        )
    }
}
