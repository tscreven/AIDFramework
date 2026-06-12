import Foundation

struct GlucoseRecord: Codable {
    let timestamp: Date
    let glucose: Decimal
}

enum PumpEventType: String, Codable {
    case tempBasal
    case smb
}

struct PumpEventRecord: Codable {
    let id: String
    let timestamp: Date
    let type: PumpEventType
    let rate: Decimal?
    let duration: Int?
    let amount: Decimal?
}

struct CarbRecord: Codable {
    let id: String
    let timestamp: Date
    let carbs: Decimal
}

struct TDDRecord: Codable {
    let timestamp: Date
    let total: Decimal
}
