import Foundation
import OrefSwiftModels

public extension Int {
    var minutesToSeconds: TimeInterval {
        Double(self * 60)
    }

    var hoursToSeconds: TimeInterval {
        Double(minutesToSeconds * 60)
    }
}

extension Decimal {
    var hoursToSeconds: TimeInterval {
        Double(minutesToSeconds * 60)
    }
}

extension TimeInterval {
    var secondsToMinutes: Decimal {
        Decimal(self / 60)
    }

    init(hours: Double) {
        self = hours * 60 * 60
    }
}
