import Foundation

public struct BloodGlucose: JSON, Identifiable, Hashable, Codable {
    public enum Direction: String, JSON {
        case tripleUp = "TripleUp"
        case doubleUp = "DoubleUp"
        case singleUp = "SingleUp"
        case fortyFiveUp = "FortyFiveUp"
        case flat = "Flat"
        case fortyFiveDown = "FortyFiveDown"
        case singleDown = "SingleDown"
        case doubleDown = "DoubleDown"
        case tripleDown = "TripleDown"
        case none = "NONE"
        case notComputable = "NOT COMPUTABLE"
        case rateOutOfRange = "RATE OUT OF RANGE"

        public init?(from string: String) {
            switch string {
            case "\u{2191}\u{2191}\u{2191}",
                 "TripleUp":
                self = .tripleUp
            case "\u{2191}\u{2191}",
                 "DoubleUp":
                self = .doubleUp
            case "\u{2191}",
                 "SingleUp":
                self = .singleUp
            case "\u{2197}",
                 "FortyFiveUp":
                self = .fortyFiveUp
            case "\u{2192}",
                 "Flat":
                self = .flat
            case "\u{2198}",
                 "FortyFiveDown":
                self = .fortyFiveDown
            case "\u{2193}",
                 "SingleDown":
                self = .singleDown
            case "\u{2193}\u{2193}",
                 "DoubleDown":
                self = .doubleDown
            case "\u{2193}\u{2193}\u{2193}",
                 "TripleDown":
                self = .tripleDown
            case "\u{2194}",
                 "NONE":
                self = .none
            case "NOT COMPUTABLE":
                self = .notComputable
            case "RATE OUT OF RANGE":
                self = .rateOutOfRange
            default:
                return nil
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case _id
        case idKey = "id"
        case sgv
        case direction
        case date
        case dateString
        case unfiltered
        case filtered
        case noise
        case glucose
        case type
        case activationDate
        case sessionStartDate
        case transmitterID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let idValue = try container.decodeIfPresent(String.self, forKey: ._id) {
            _id = idValue
        } else {
            _id = try container.decode(String.self, forKey: .idKey)
        }

        sgv = try? container.decodeIfPresent(Int.self, forKey: .sgv)
        if sgv == nil {
            if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: .sgv) {
                sgv = Int(doubleValue)
            }
        }

        direction = try container.decodeIfPresent(Direction.self, forKey: .direction)
        dateString = try container.decode(Date.self, forKey: .dateString)

        do {
            date = try container.decode(Decimal.self, forKey: .date)
        } catch {
            date = Decimal(dateString.timeIntervalSince1970 * 1000).rounded()
        }

        unfiltered = try container.decodeIfPresent(Decimal.self, forKey: .unfiltered)
        filtered = try container.decodeIfPresent(Decimal.self, forKey: .filtered)
        noise = try container.decodeIfPresent(Int.self, forKey: .noise)
        glucose = try container.decodeIfPresent(Int.self, forKey: .glucose)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        activationDate = try container.decodeIfPresent(Date.self, forKey: .activationDate)
        sessionStartDate = try container.decodeIfPresent(Date.self, forKey: .sessionStartDate)
        transmitterID = try container.decodeIfPresent(String.self, forKey: .transmitterID)
    }

    public init(
        _id: String = UUID().uuidString,
        sgv: Int? = nil,
        direction: Direction? = nil,
        date: Decimal,
        dateString: Date,
        unfiltered: Decimal? = nil,
        filtered: Decimal? = nil,
        noise: Int? = nil,
        glucose: Int? = nil,
        type: String? = nil,
        activationDate: Date? = nil,
        sessionStartDate: Date? = nil,
        transmitterID: String? = nil
    ) {
        self._id = _id
        self.sgv = sgv
        self.direction = direction
        self.date = date
        self.dateString = dateString
        self.unfiltered = unfiltered
        self.filtered = filtered
        self.noise = noise
        self.glucose = glucose
        self.type = type
        self.activationDate = activationDate
        self.sessionStartDate = sessionStartDate
        self.transmitterID = transmitterID
    }

    public var _id: String?
    public var id: String {
        _id ?? UUID().uuidString
    }

    public var idKey: String?

    public var sgv: Int?
    public var direction: Direction?
    public let date: Decimal
    public let dateString: Date
    public let unfiltered: Decimal?
    public let filtered: Decimal?
    public let noise: Int?
    public var glucose: Int?
    public var type: String? = nil
    public var activationDate: Date? = nil
    public var sessionStartDate: Date? = nil
    public var transmitterID: String? = nil
    public var isStateValid: Bool { sgv ?? 0 >= 39 && noise ?? 1 != 4 }

    public static func == (lhs: BloodGlucose, rhs: BloodGlucose) -> Bool {
        lhs.dateString == rhs.dateString
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(dateString)
    }
}
