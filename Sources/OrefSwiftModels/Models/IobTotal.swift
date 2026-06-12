import Foundation

public struct IobTotal: Codable {
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
