import Foundation
import OrefSwiftModels

public struct IobHistory {
    public static let MAX_PUMP_HISTORY_HOURS: Double = 36

    struct PumpSuspended {
        let timestamp: Date
        let durationInMinutes: Decimal
        let isSuspendedPrior: Bool
        let isCurrentlySuspended: Bool

        init(timestamp: Date, durationInMinutes: Decimal, isSuspendedPrior: Bool = false, isCurrentlySuspended: Bool = false) {
            self.timestamp = timestamp
            self.durationInMinutes = durationInMinutes
            self.isSuspendedPrior = isSuspendedPrior
            self.isCurrentlySuspended = isCurrentlySuspended
        }

        var end: Date {
            timestamp + durationInMinutes.minutesToSeconds
        }

        func doesOverlap(with event: ComputedPumpHistoryEvent) -> Bool {
            guard let eventDuration = event.duration else {
                return event.timestamp >= timestamp && event.timestamp < end
            }
            let eventEnd = event.timestamp + eventDuration.minutesToSeconds

            return event.timestamp < end && timestamp < eventEnd
        }
    }

    private static func getTempBasals(
        pumpHistory: [ComputedPumpHistoryEvent],
        clock: Date,
        zeroTempDuration: Decimal?
    ) throws -> [ComputedPumpHistoryEvent] {
        let tempBasals = pumpHistory.filter { $0.type == .tempBasal }
        let durations = pumpHistory.filter { $0.type == .tempBasalDuration }

        guard tempBasals.count == durations.count else {
            throw IobError.tempBasalDurationMismatch
        }

        let zeroTempBasal = ComputedPumpHistoryEvent.zeroTempBasal(
            timestamp: clock + 1.minutesToSeconds,
            duration: zeroTempDuration ?? 0,
            omitFromTempHistory: false
        )

        let unifiedTempBasals = try zip(tempBasals, durations).map { tempBasal, duration in
            guard tempBasal.timestamp == duration.timestamp else {
                throw IobError.tempBasalDurationMismatch
            }

            guard let duration = duration.durationMin else {
                throw IobError.tempBasalDurationMissingDuration(timestamp: duration.timestamp)
            }

            return tempBasal.copyWith(duration: Decimal(duration))
        } + [zeroTempBasal]

        let alignedTempBasals = zip(unifiedTempBasals, unifiedTempBasals.dropFirst()).map { curr, next in
            let currEnd = curr.timestamp + (curr.duration?.minutesToSeconds ?? 0)
            if currEnd > next.timestamp {
                let newDuration = next.timestamp.timeIntervalSince(curr.timestamp).secondsToMinutes
                return curr.copyWith(duration: newDuration)
            } else {
                return curr
            }
        }

        return alignedTempBasals + (unifiedTempBasals.last.map { [$0] } ?? [])
    }

    private static func getSuspends(
        pumpHistory: [ComputedPumpHistoryEvent],
        clock: Date
    ) throws -> [PumpSuspended] {
        let pumpSuspendResumeFull = pumpHistory.filter { $0.type == .pumpSuspend || $0.type == .pumpResume }

        let pumpSuspendResume = pumpSuspendResumeFull.reduce(into: [ComputedPumpHistoryEvent]()) { result, event in
            if result.last?.type != event.type {
                result.append(event)
            }
        }

        for (curr, next) in zip(pumpSuspendResume, pumpSuspendResume.dropFirst()) {
            guard curr.type != next.type, curr.timestamp != next.timestamp else {
                throw IobError.pumpSuspendResumeMismatch
            }
        }

        var suspends = zip(pumpSuspendResume, pumpSuspendResume.dropFirst()).compactMap { curr, next -> PumpSuspended? in
            if curr.type == .pumpResume {
                return nil
            } else {
                let duration = next.timestamp.timeIntervalSince(curr.timestamp).secondsToMinutes
                return PumpSuspended(timestamp: curr.timestamp, durationInMinutes: duration)
            }
        }

        let maxPumpHistoryAgo = clock - TimeInterval(hours: MAX_PUMP_HISTORY_HOURS)
        if let first = pumpSuspendResume.first, first.type == .pumpResume, maxPumpHistoryAgo < first.timestamp {
            let start = maxPumpHistoryAgo
            let duration = first.timestamp.timeIntervalSince(start).secondsToMinutes
            suspends.append(PumpSuspended(timestamp: start, durationInMinutes: duration, isSuspendedPrior: true))
        }

        if let last = pumpSuspendResume.last, last.type == .pumpSuspend {
            let duration = clock.timeIntervalSince(last.timestamp).secondsToMinutes
            suspends.append(PumpSuspended(timestamp: last.timestamp, durationInMinutes: duration, isCurrentlySuspended: true))
        }

        return suspends.sorted { $0.timestamp < $1.timestamp }
    }

    private static func modifyTempBasalDuringSuspend(
        tempBasal: ComputedPumpHistoryEvent,
        suspends: [PumpSuspended]
    ) -> [ComputedPumpHistoryEvent] {
        guard let tempBasalDuration = tempBasal.duration, tempBasalDuration != 0 else {
            return [tempBasal]
        }

        for (index, suspend) in suspends.enumerated() {
            if suspend.doesOverlap(with: tempBasal) {
                let tempBasalStartsBeforeSuspend = tempBasal.timestamp < suspend.timestamp
                let tempBasalEnd = tempBasal.timestamp + tempBasalDuration.minutesToSeconds
                let tempBasalEndsAfterSuspend = tempBasalEnd > suspend.end

                switch (tempBasalStartsBeforeSuspend, tempBasalEndsAfterSuspend) {
                case (false, false):
                    return []
                case (true, false):
                    let newDuration = suspend.timestamp.timeIntervalSince(tempBasal.timestamp).secondsToMinutes
                    return [tempBasal.copyWith(duration: newDuration)]
                case (false, true):
                    let newDuration = tempBasalEnd.timeIntervalSince(suspend.end).secondsToMinutes
                    let newTempBasal = tempBasal.copyWith(
                        duration: newDuration,
                        timestamp: suspend.end
                    )
                    return modifyTempBasalDuringSuspend(tempBasal: newTempBasal, suspends: Array(suspends.dropFirst(index + 1)))
                case (true, true):
                    let firstDuration = suspend.timestamp.timeIntervalSince(tempBasal.timestamp).secondsToMinutes
                    let firstTempBasal = tempBasal.copyWith(duration: firstDuration)
                    let secondDuration = tempBasalEnd.timeIntervalSince(suspend.end).secondsToMinutes
                    let secondTempBasal = tempBasal.copyWith(
                        duration: secondDuration,
                        timestamp: suspend.end,
                        omitFromTempHistory: true
                    )
                    return [firstTempBasal] +
                        modifyTempBasalDuringSuspend(tempBasal: secondTempBasal, suspends: Array(suspends.dropFirst(index + 1)))
                }
            }
        }

        return [tempBasal]
    }

    private static func adjustForCurrentlySuspended(
        tempBasals: [ComputedPumpHistoryEvent],
        suspends: [PumpSuspended]
    ) -> [ComputedPumpHistoryEvent] {
        guard let lastSuspend = suspends.last, lastSuspend.isCurrentlySuspended else {
            return tempBasals
        }
        return tempBasals
    }

    private static func adjustForSuspendedPrior(
        tempBasals: [ComputedPumpHistoryEvent],
        suspends: [PumpSuspended]
    ) -> [ComputedPumpHistoryEvent] {
        guard let firstSuspend = suspends.first, firstSuspend.isSuspendedPrior else {
            return tempBasals
        }

        let firstResumeDate = firstSuspend.end
        return tempBasals.map { event in
            let eventStartsBeforeResume = event.timestamp < firstResumeDate
            guard eventStartsBeforeResume else {
                return event
            }

            if event.end < firstResumeDate {
                return event.copyWith(duration: 0)
            } else {
                let newDuration = event.end.timeIntervalSince(firstResumeDate).secondsToMinutes
                return event.copyWith(duration: newDuration, timestamp: firstResumeDate)
            }
        }
    }

    private static func splitAroundSuspends(
        tempBasals: [ComputedPumpHistoryEvent],
        suspends: [PumpSuspended]
    ) -> [ComputedPumpHistoryEvent] {
        var tempBasals = adjustForSuspendedPrior(tempBasals: tempBasals, suspends: suspends)
        tempBasals = adjustForCurrentlySuspended(tempBasals: tempBasals, suspends: suspends)
        tempBasals = tempBasals.flatMap { modifyTempBasalDuringSuspend(tempBasal: $0, suspends: suspends) }
        let zeroTempBasals = suspends
            .map {
                ComputedPumpHistoryEvent
                    .zeroTempBasal(timestamp: $0.timestamp, duration: $0.durationInMinutes, omitFromTempHistory: true)
            }

        return (tempBasals + zeroTempBasals).sorted { $0.timestamp < $1.timestamp }
    }

    private static func splitAtMinutesSinceMidnight(
        tempBasal: ComputedPumpHistoryEvent,
        splitPoint: Decimal
    ) throws -> [ComputedPumpHistoryEvent] {
        guard let startMinutes = tempBasal.timestamp.minutesSinceMidnight.map({ Decimal($0) }) else {
            throw CalendarError.invalidCalendar
        }

        guard let duration = tempBasal.duration else {
            throw IobError.tempBasalDurationMissingDuration(timestamp: tempBasal.timestamp)
        }

        let event1Duration = splitPoint - startMinutes
        let event2Duration = duration - event1Duration
        let event2Start = tempBasal.timestamp + event1Duration.minutesToSeconds

        return [
            tempBasal.copyWith(duration: event1Duration),
            tempBasal.copyWith(duration: event2Duration, timestamp: event2Start)
        ]
    }

    private static func splitAtProfileBreak(
        tempBasal: ComputedPumpHistoryEvent,
        profileBreaks: [Decimal]
    ) throws -> [ComputedPumpHistoryEvent] {
        guard let duration = tempBasal.duration else {
            throw IobError.tempBasalMissingDuration(timestamp: tempBasal.timestamp)
        }

        guard let startMinutes = tempBasal.timestamp.minutesSinceMidnightWithPrecision else {
            throw CalendarError.invalidCalendar
        }

        let endMinutes = startMinutes + duration
        for profileBreak in profileBreaks {
            if profileBreak > startMinutes, profileBreak < endMinutes {
                return try splitAtMinutesSinceMidnight(tempBasal: tempBasal, splitPoint: profileBreak)
            }
        }

        return [tempBasal]
    }

    private static func splitAtMidnight(tempBasal: ComputedPumpHistoryEvent) throws -> [ComputedPumpHistoryEvent] {
        let minutesPerDay = Decimal(24 * 60)
        guard let startMinutes = tempBasal.timestamp.minutesSinceMidnightWithPrecision else {
            throw CalendarError.invalidCalendar
        }

        guard let duration = tempBasal.duration else {
            throw IobError.tempBasalMissingDuration(timestamp: tempBasal.timestamp)
        }

        let endMinutes = startMinutes + duration
        if endMinutes > minutesPerDay {
            return try splitAtMinutesSinceMidnight(tempBasal: tempBasal, splitPoint: minutesPerDay)
        } else {
            return [tempBasal]
        }
    }

    private static func splitBy30mDuration(tempBasal: ComputedPumpHistoryEvent) throws -> [ComputedPumpHistoryEvent] {
        guard let duration = tempBasal.duration else {
            throw IobError.tempBasalMissingDuration(timestamp: tempBasal.timestamp)
        }

        return stride(from: tempBasal.timestamp, to: tempBasal.timestamp + duration.minutesToSeconds, by: 30.minutesToSeconds)
            .map { start in
                let endOfChunk = start + 30.minutesToSeconds
                let endOfTempBasal = tempBasal.timestamp + duration.minutesToSeconds
                let end = min(endOfChunk, endOfTempBasal)
                let durationInSeconds = end.timeIntervalSince(start)

                return tempBasal.copyWith(duration: durationInSeconds.secondsToMinutes, timestamp: start)
            }
    }

    private static func splitTempBasal(
        tempBasal: ComputedPumpHistoryEvent,
        profileBreaks: [Decimal]
    ) throws -> [ComputedPumpHistoryEvent] {
        try splitBy30mDuration(tempBasal: tempBasal)
            .flatMap({ try splitAtMidnight(tempBasal: $0) })
            .flatMap({ try splitAtProfileBreak(tempBasal: $0, profileBreaks: profileBreaks) })
    }

    private static func extractTempBoluses(
        from tempBasal: ComputedPumpHistoryEvent,
        profile: Profile,
        autosens: Autosens?
    ) throws -> [ComputedPumpHistoryEvent] {
        guard let duration = tempBasal.duration, duration > 0 else {
            return []
        }

        guard let tempBasalRate = tempBasal.rate else {
            throw IobError.rateNotSetOnTempBasal(timestamp: tempBasal.timestamp)
        }

        guard let profileCurrentRate = try Basal.basalLookup(profile.basalprofile ?? [], now: tempBasal.timestamp) ?? profile
            .currentBasal
        else {
            throw IobError.basalRateNotSet
        }

        let currentRate = autosens.map { $0.ratio * profileCurrentRate } ?? profileCurrentRate

        let netBasalRate = tempBasalRate - currentRate
        let tempBolusSize: Decimal = netBasalRate < 0 ? -0.05 : 0.05

        let netBasalAmountTmp = (netBasalRate * duration * 10 / 6).jsRounded()
        let netBasalAmount = netBasalAmountTmp / Decimal(100)
        let tempBolusCount = Int((netBasalAmount / tempBolusSize).rounded())

        let tempBolusSpacing = Decimal(duration.minutesToSeconds) / Decimal(tempBolusCount)

        return (0 ..< tempBolusCount).map { j in
            let timestamp = tempBasal.timestamp + Double(j) * Double(tempBolusSpacing)
            return ComputedPumpHistoryEvent.tempBolus(timestamp: timestamp, insulin: tempBolusSize)
        }
    }

    private static func convertTempBasalToBolus(
        tempHistory: [ComputedPumpHistoryEvent],
        profile: Profile,
        autosens: Autosens?
    ) throws -> [ComputedPumpHistoryEvent] {
        let profileBreaksMinutesSinceMidnight = profile.basalprofile?.map({ Decimal($0.minutes) }) ?? []
        let splitTempBasals = try tempHistory
            .flatMap { try splitTempBasal(tempBasal: $0, profileBreaks: profileBreaksMinutesSinceMidnight) }
        return try splitTempBasals
            .flatMap { try extractTempBoluses(from: $0, profile: profile, autosens: autosens) }
    }

    public static func calcTempTreatments(
        history: [ComputedPumpHistoryEvent],
        profile: Profile,
        clock: Date,
        autosens: Autosens?,
        zeroTempDuration: Decimal?
    ) throws -> [ComputedPumpHistoryEvent] {
        let pumpHistory = history.filter({ $0.timestamp <= clock }).sorted { $0.timestamp < $1.timestamp }
        let tempBasals = try getTempBasals(pumpHistory: pumpHistory, clock: clock, zeroTempDuration: zeroTempDuration)
        let suspends = try getSuspends(pumpHistory: pumpHistory, clock: clock)
        let boluses = pumpHistory.filter({ $0.type == .bolus }).map { $0.copyWith(insulin: $0.amount) }

        var tempHistory: [ComputedPumpHistoryEvent]
        if profile.suspendZerosIob {
            tempHistory = splitAroundSuspends(tempBasals: tempBasals, suspends: suspends)
        } else {
            tempHistory = tempBasals
        }

        let tempBoluses = try convertTempBasalToBolus(
            tempHistory: tempHistory,
            profile: profile,
            autosens: autosens
        )

        tempHistory = tempHistory.filter { !$0.omitFromTempHistory }

        return (boluses + tempBoluses + tempHistory).sorted { $0.timestamp < $1.timestamp }
    }
}
