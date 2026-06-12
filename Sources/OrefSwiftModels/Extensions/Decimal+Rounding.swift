import Foundation

public extension Decimal {
    func rounded(scale: Int, roundingMode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        let handler = NSDecimalNumberHandler(
            roundingMode: roundingMode,
            scale: Int16(scale),
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: self).rounding(accordingToBehavior: handler).decimalValue
    }

    func rounded() -> Decimal {
        rounded(scale: 0)
    }

    func jsRounded(scale: Int) -> Decimal {
        let multiplier = (0 ..< scale).reduce(Decimal(1)) { result, _ in result * 10 }
        return (self * multiplier + 0.5).rounded(scale: 0, roundingMode: .down) / multiplier
    }

    func jsRounded() -> Decimal {
        jsRounded(scale: 6).jsRounded(scale: 0)
    }
}

public extension Decimal {
    var minutesToSeconds: TimeInterval {
        Double(self * 60)
    }

    func clamp(lowerBound: Decimal, upperBound: Decimal) -> Decimal {
        if self < lowerBound {
            return lowerBound
        } else if self > upperBound {
            return upperBound
        } else {
            return self
        }
    }

    func floor() -> Decimal {
        rounded(scale: 0, roundingMode: .down)
    }

    func rounded(toPlaces places: Int) -> Decimal {
        rounded(scale: places)
    }

    var asMmolL: Decimal {
        (self * GlucoseUnits.exchangeRate).rounded(scale: 1)
    }
}

public extension Collection where Element == Decimal {
    var mean: Decimal {
        guard !isEmpty else { return .zero }
        return reduce(.zero, +) / Decimal(count)
    }
}
