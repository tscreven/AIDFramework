import Foundation

public extension Int {
    init(_ decimal: Decimal) {
        self.init(Double(decimal))
    }
}
