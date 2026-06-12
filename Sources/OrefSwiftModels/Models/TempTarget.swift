import Foundation

public struct TempTarget: JSON, Identifiable, Equatable, Hashable {
    public var id: String
    public let name: String?
    public var createdAt: Date
    public let targetTop: Decimal?
    public let targetBottom: Decimal?
    public let duration: Decimal
    public let enteredBy: String?
    public let reason: String?
    public let isPreset: Bool?
    public var enabled: Bool?
    public let halfBasalTarget: Decimal?

    public static let local = "Trio"
    public static let custom = "Temp Target"
    public static let cancel = "Cancel"

    public var displayName: String {
        name ?? reason ?? TempTarget.custom
    }

    public static func == (lhs: TempTarget, rhs: TempTarget) -> Bool {
        lhs.createdAt == rhs.createdAt
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(createdAt)
    }

    public init(
        id: String = UUID().uuidString,
        name: String?,
        createdAt: Date,
        targetTop: Decimal?,
        targetBottom: Decimal?,
        duration: Decimal,
        enteredBy: String?,
        reason: String?,
        isPreset: Bool?,
        enabled: Bool?,
        halfBasalTarget: Decimal?
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.targetTop = targetTop
        self.targetBottom = targetBottom
        self.duration = duration
        self.enteredBy = enteredBy
        self.reason = reason
        self.isPreset = isPreset
        self.enabled = enabled
        self.halfBasalTarget = halfBasalTarget
    }

    public static func cancel(at date: Date) -> TempTarget {
        TempTarget(
            name: TempTarget.cancel,
            createdAt: date,
            targetTop: 0,
            targetBottom: 0,
            duration: 0,
            enteredBy: TempTarget.local,
            reason: TempTarget.cancel,
            isPreset: nil,
            enabled: nil,
            halfBasalTarget: 160
        )
    }
}

extension TempTarget {
    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
        case createdAt = "created_at"
        case targetTop
        case targetBottom
        case duration
        case enteredBy
        case reason
        case isPreset
        case enabled
        case halfBasalTarget
    }
}
