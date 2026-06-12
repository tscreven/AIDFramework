import Foundation

public extension Double {
    var decimal: Decimal? {
        Decimal(string: String(self))
    }

    init(_ decimal: Decimal) {
        self.init(truncating: decimal as NSNumber)
    }

    func clamp(lowerBound: Double, upperBound: Double) -> Double {
        if self < lowerBound {
            return lowerBound
        } else if self > upperBound {
            return upperBound
        } else {
            return self
        }
    }
}
