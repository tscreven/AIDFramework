import Foundation

public enum CalendarError: LocalizedError, Equatable {
    case invalidCalendar
    case invalidCalendarHourOnly

    public var errorDescription: String? {
        switch self {
        case .invalidCalendar:
            return "Unable to extract hours and minutes from the current calendar"
        case .invalidCalendarHourOnly:
            return "Unable to extract hours from the current calendar"
        }
    }
}

public extension Date {
    var hourInLocalTime: Int? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour], from: self)
        return components.hour
    }

    var minutesSinceMidnight: Int? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: self)
        guard let hour = components.hour, let minute = components.minute else {
            return nil
        }
        return hour * 60 + minute
    }

    var minutesSinceMidnightWithPrecision: Decimal? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: self)

        guard let hour = components.hour,
              let minute = components.minute,
              let second = components.second,
              let nanosecond = components.nanosecond
        else {
            return nil
        }

        let milliseconds = (Decimal(nanosecond) / 1_000_000).rounded()
        let baseMinutes = Decimal(hour * 60 + minute)
        let secondsAsMinutes = Decimal(second) / Decimal(60)
        let millisecondsAsMinutes = milliseconds / Decimal(60000)

        return baseMinutes + secondsAsMinutes + millisecondsAsMinutes
    }

    func isMinutesFromMidnightWithinRange(lowerBound: Int, upperBound: Int) throws -> Bool {
        guard let currentMinutes = minutesSinceMidnight else {
            throw CalendarError.invalidCalendar
        }
        return currentMinutes >= lowerBound && currentMinutes < upperBound
    }

    func roundedToNearestMinute() -> Date {
        let timestampInMinutes = timeIntervalSince1970.secondsToMinutes
        let timestampRounded = timestampInMinutes.rounded()
        return Date(timeIntervalSince1970: Double(timestampRounded) * 60)
    }
}
