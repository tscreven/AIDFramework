import Foundation
import OrefSwiftAlgorithm
import OrefSwiftModels

struct SimulationStorage {
    let stateDir: String

    // MARK: - File paths

    private var glucosePath: String { "\(stateDir)/glucose.json" }
    private var pumpHistoryPath: String { "\(stateDir)/pump_history.json" }
    private var carbsPath: String { "\(stateDir)/carbs.json" }
    private var autosensPath: String { "\(stateDir)/autosens.json" }
    private var settingsPath: String { "\(stateDir)/settings.json" }
    private var profilePath: String { "\(stateDir)/profile.json" }

    // Therapy settings files (matching virtual user directory layout)
    private var preferencesPath: String { "\(stateDir)/preferences.json" }
    private var pumpSettingsPath: String { "\(stateDir)/settings.json" }
    private var bgTargetsPath: String { "\(stateDir)/bg_targets.json" }
    private var basalProfilePath: String { "\(stateDir)/basal_profile.json" }
    private var insulinSensitivitiesPath: String { "\(stateDir)/insulin_sensitivities.json" }
    private var carbRatiosPath: String { "\(stateDir)/carb_ratios.json" }
    private var tempTargetsPath: String { "\(stateDir)/temptargets.json" }
    private var tddPath: String { "\(stateDir)/tdd.json" }

    // MARK: - Generic helpers

    private func load<T: Decodable>(_ type: T.Type, from path: String) throws -> T {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONCoding.decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to path: String) throws {
        let data = try JSONCoding.encoder.encode(value)
        try data.write(to: URL(fileURLWithPath: path))
    }

    // Fast encoder/decoder for internal storage records that don't need
    // ISO8601 string formatting. Uses secondsSince1970 (numeric timestamps)
    // which avoids the expensive ISO8601DateFormatter.
    private static let fastEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let fastDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private func loadFast<T: Decodable>(_ type: T.Type, from path: String) throws -> T {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try Self.fastDecoder.decode(T.self, from: data)
    }

    private func saveFast<T: Encodable>(_ value: T, to path: String) throws {
        let data = try Self.fastEncoder.encode(value)
        try data.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Glucose

    // Maximum lookback windows for pruning stored data. If any algorithm
    // query is changed to look back further than these windows, these
    // constants MUST be updated to match. See Docs/simulation.md for details.
    private static let glucoseRetention: TimeInterval = 24 * 60 * 60       // 24 hours
    private static let pumpHistoryRetention: TimeInterval = 24 * 60 * 60   // 24 hours
    private static let carbsRetention: TimeInterval = 24 * 60 * 60         // 24 hours
    private static let tddRetention: TimeInterval = 10 * 24 * 60 * 60     // 10 days

    func storeGlucose(at timestamp: Date, glucose: Decimal) throws {
        var records = try loadFast([GlucoseRecord].self, from: glucosePath)
        records.append(GlucoseRecord(timestamp: timestamp, glucose: glucose))
        let cutoff = timestamp.addingTimeInterval(-Self.glucoseRetention)
        records.removeAll { $0.timestamp <= cutoff }
        try saveFast(records, to: glucosePath)
    }

    func fetchGlucose(at timestamp: Date, limit: Int? = nil) -> [BloodGlucose] {
        guard let records = try? loadFast([GlucoseRecord].self, from: glucosePath) else {
            return []
        }

        let cutoff = timestamp.addingTimeInterval(-24 * 60 * 60)
        let filtered = records
            .filter { $0.timestamp > cutoff && $0.timestamp <= timestamp }
            .sorted { $0.timestamp > $1.timestamp }

        let limited: [GlucoseRecord]
        if let limit = limit {
            limited = Array(filtered.prefix(limit))
        } else {
            limited = filtered
        }

        return limited.enumerated().map { index, record in
            let sgv = NSDecimalNumber(decimal: record.glucose).intValue

            // Compute direction from consecutive readings (next in array = previous in time)
            let direction: BloodGlucose.Direction
            if index + 1 < limited.count {
                let previousSgv = NSDecimalNumber(decimal: limited[index + 1].glucose).intValue
                direction = DirectionCalculator.direction(from: sgv - previousSgv)
            } else {
                direction = .flat
            }

            return BloodGlucose(
                _id: UUID().uuidString,
                sgv: sgv,
                direction: direction,
                date: Decimal(record.timestamp.timeIntervalSince1970 * 1000),
                dateString: record.timestamp,
                noise: 0,
                glucose: sgv
            )
        }
    }

    // MARK: - Pump events

    /// Load raw pump event records from disk once for reuse across multiple queries.
    func loadPumpEventRecords() -> [PumpEventRecord] {
        (try? loadFast([PumpEventRecord].self, from: pumpHistoryPath)) ?? []
    }

    func storeTempBasal(at timestamp: Date, rate: Decimal, duration: Int) throws {
        var records = try loadFast([PumpEventRecord].self, from: pumpHistoryPath)
        records.append(PumpEventRecord(
            id: UUID().uuidString,
            timestamp: timestamp,
            type: .tempBasal,
            rate: rate,
            duration: duration,
            amount: nil
        ))
        let cutoff = timestamp.addingTimeInterval(-Self.pumpHistoryRetention)
        records.removeAll { $0.timestamp <= cutoff }
        try saveFast(records, to: pumpHistoryPath)
    }

    func storeSMB(at timestamp: Date, amount: Decimal) throws {
        var records = try loadFast([PumpEventRecord].self, from: pumpHistoryPath)
        records.append(PumpEventRecord(
            id: UUID().uuidString,
            timestamp: timestamp,
            type: .smb,
            rate: nil,
            duration: nil,
            amount: amount
        ))
        let cutoff = timestamp.addingTimeInterval(-Self.pumpHistoryRetention)
        records.removeAll { $0.timestamp <= cutoff }
        try saveFast(records, to: pumpHistoryPath)
    }

    func fetchPumpEvents(at timestamp: Date) -> [PumpHistoryEvent] {
        fetchPumpEvents(at: timestamp, from: loadPumpEventRecords())
    }

    func fetchPumpEvents(at timestamp: Date, from records: [PumpEventRecord]) -> [PumpHistoryEvent] {
        let cutoff = timestamp.addingTimeInterval(-24 * 60 * 60)
        let filtered = records.filter { $0.timestamp > cutoff && $0.timestamp <= timestamp }

        return filtered.flatMap { record -> [PumpHistoryEvent] in
            switch record.type {
            case .tempBasal:
                let durationEvent = PumpHistoryEvent(
                    id: record.id,
                    type: .tempBasalDuration,
                    timestamp: record.timestamp,
                    durationMin: record.duration
                )
                let rateEvent = PumpHistoryEvent(
                    id: "_\(record.id)",
                    type: .tempBasal,
                    timestamp: record.timestamp,
                    rate: record.rate,
                    temp: .absolute
                )
                return [durationEvent, rateEvent]

            case .smb:
                let bolusEvent = PumpHistoryEvent(
                    id: record.id,
                    type: .bolus,
                    timestamp: record.timestamp,
                    amount: record.amount,
                    isSMB: true
                )
                return [bolusEvent]

            case .pumpResume:
                return [PumpHistoryEvent(id: record.id, type: .pumpResume, timestamp: record.timestamp)]

            case .pumpSuspend:
                return [PumpHistoryEvent(id: record.id, type: .pumpSuspend, timestamp: record.timestamp)]
            }
        }
    }

    func fetchCurrentTempBasal(at timestamp: Date) -> TempBasal {
        fetchCurrentTempBasal(at: timestamp, from: loadPumpEventRecords())
    }

    func fetchCurrentTempBasal(at timestamp: Date, from records: [PumpEventRecord]) -> TempBasal {
        let defaultBasal = TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: timestamp)

        let lookback = timestamp.addingTimeInterval(-20 * 60)
        let recentTempBasal = records
            .filter { $0.type == .tempBasal && $0.timestamp > lookback && $0.timestamp <= timestamp }
            .sorted { $0.timestamp > $1.timestamp }
            .first

        guard let tempBasal = recentTempBasal,
              let duration = tempBasal.duration
        else {
            return defaultBasal
        }

        let elapsedMinutes = Int(timestamp.timeIntervalSince(tempBasal.timestamp) / 60)
        let remainingDuration = duration - elapsedMinutes

        if remainingDuration <= 0 {
            return defaultBasal
        }

        return TempBasal(
            duration: remainingDuration,
            rate: tempBasal.rate ?? 0,
            temp: .absolute,
            timestamp: tempBasal.timestamp
        )
    }

    // MARK: - Carbs

    func storeCarbs(at timestamp: Date, carbs: Decimal) throws {
        var records = try loadFast([CarbRecord].self, from: carbsPath)
        records.append(CarbRecord(id: UUID().uuidString, timestamp: timestamp, carbs: carbs))
        let cutoff = timestamp.addingTimeInterval(-Self.carbsRetention)
        records.removeAll { $0.timestamp <= cutoff }
        try saveFast(records, to: carbsPath)
    }

    func fetchCarbs(at timestamp: Date) -> [CarbsEntry] {
        guard let records = try? loadFast([CarbRecord].self, from: carbsPath) else {
            return []
        }

        let cutoff = timestamp.addingTimeInterval(-24 * 60 * 60)
        let filtered = records.filter { $0.timestamp > cutoff && $0.timestamp <= timestamp }

        return filtered.map { record in
            CarbsEntry(
                id: record.id,
                createdAt: record.timestamp,
                actualDate: record.timestamp,
                carbs: record.carbs,
                isFPU: false
            )
        }
    }

    // MARK: - TDD (Total Daily Dose)

    /// Appends a TDD record, prunes old entries, saves to disk, and returns the pruned records.
    @discardableResult
    func storeTDD(at timestamp: Date, total: Decimal) throws -> [TDDRecord] {
        var records = (try? loadFast([TDDRecord].self, from: tddPath)) ?? []
        records.append(TDDRecord(timestamp: timestamp, total: total))
        let cutoff = timestamp.addingTimeInterval(-Self.tddRetention)
        records.removeAll { $0.timestamp <= cutoff }
        try saveFast(records, to: tddPath)
        return records
    }

    /// Calculate TDD from pump history and basal profile over the last 24 hours.
    ///
    /// TempBasal commands are mutually exclusive on real pumps: a new TempBasal
    /// implicitly cancels any previously running one. This method truncates
    /// overlapping TempBasal durations so that each command only contributes
    /// insulin up until the next TempBasal command starts.
    ///
    /// Note: Real pumps quantize insulin delivery, but the simulation ignores
    /// this quantization for simplicity.
    func calculateTDD(at timestamp: Date, basalProfile: [BasalProfileEntry], from records: [PumpEventRecord]) -> Decimal {
        let cutoff = timestamp.addingTimeInterval(-24 * 60 * 60)
        let recent = records.filter { $0.timestamp > cutoff && $0.timestamp <= timestamp }

        // Sum bolus (SMB) insulin
        let bolusInsulin = recent
            .filter { $0.type == .smb }
            .compactMap { $0.amount }
            .reduce(Decimal(0), +)

        // Build effective temp basal intervals, truncating overlaps.
        // A newer TempBasal command cancels any previously running one,
        // so each command's effective duration ends at the earlier of its
        // nominal end time or the start of the next TempBasal command.
        let tempBasalEvents = recent
            .filter { $0.type == .tempBasal }
            .sorted { $0.timestamp < $1.timestamp }

        let effectiveIntervals = buildEffectiveTempBasalIntervals(
            tempBasalEvents: tempBasalEvents,
            cutoff: cutoff,
            now: timestamp
        )

        // Sum temp basal insulin using effective (truncated) durations
        let tempBasalInsulin = effectiveIntervals.reduce(Decimal(0)) { sum, interval in
            let hours = Decimal(interval.end.timeIntervalSince(interval.start)) / 3600
            return sum + interval.rate * hours
        }

        // Calculate scheduled basal insulin for gaps between temp basals
        let scheduledBasalInsulin = calculateScheduledBasalInsulin(
            at: timestamp,
            cutoff: cutoff,
            effectiveIntervals: effectiveIntervals,
            basalProfile: basalProfile
        )

        return bolusInsulin + tempBasalInsulin + scheduledBasalInsulin
    }

    private struct EffectiveTempBasalInterval {
        let start: Date
        let end: Date
        let rate: Decimal
    }

    /// Build effective temp basal intervals by truncating overlapping commands.
    /// Each TempBasal's effective duration ends at the earlier of its nominal
    /// end time or the start of the next TempBasal command.
    private func buildEffectiveTempBasalIntervals(
        tempBasalEvents: [PumpEventRecord],
        cutoff: Date,
        now: Date
    ) -> [EffectiveTempBasalInterval] {
        var intervals: [EffectiveTempBasalInterval] = []

        for (index, event) in tempBasalEvents.enumerated() {
            guard let rate = event.rate, let duration = event.duration, duration > 0 else {
                continue
            }

            let nominalEnd = event.timestamp.addingTimeInterval(Double(duration) * 60)

            // Truncate if a subsequent TempBasal starts before this one ends
            let effectiveEnd: Date
            if index + 1 < tempBasalEvents.count {
                effectiveEnd = min(nominalEnd, tempBasalEvents[index + 1].timestamp)
            } else {
                effectiveEnd = nominalEnd
            }

            // Clamp to the 24-hour window
            let clampedStart = max(event.timestamp, cutoff)
            let clampedEnd = min(effectiveEnd, now)

            if clampedEnd > clampedStart {
                intervals.append(EffectiveTempBasalInterval(
                    start: clampedStart,
                    end: clampedEnd,
                    rate: rate
                ))
            }
        }

        return intervals
    }

    /// Calculate insulin delivered by the scheduled basal rate during gaps
    /// when no temp basal was active.
    private func calculateScheduledBasalInsulin(
        at timestamp: Date,
        cutoff: Date,
        effectiveIntervals: [EffectiveTempBasalInterval],
        basalProfile: [BasalProfileEntry]
    ) -> Decimal {
        guard !basalProfile.isEmpty else { return 0 }

        struct Interval {
            let start: Date
            let end: Date
        }

        // Find gaps where scheduled basal runs
        var gaps: [Interval] = []
        var gapStart = cutoff

        for interval in effectiveIntervals {
            if interval.start > gapStart {
                gaps.append(Interval(start: gapStart, end: interval.start))
            }
            gapStart = max(gapStart, interval.end)
        }
        if gapStart < timestamp {
            gaps.append(Interval(start: gapStart, end: timestamp))
        }

        // Sum scheduled basal insulin for each gap
        var total: Decimal = 0
        for gap in gaps {
            let hours = Decimal(gap.end.timeIntervalSince(gap.start)) / 3600
            let rate = scheduledBasalRate(at: gap.start, basalProfile: basalProfile)
            total += rate * hours
        }
        return total
    }

    /// Look up the scheduled basal rate for a given time from the basal profile.
    private func scheduledBasalRate(at date: Date, basalProfile: [BasalProfileEntry]) -> Decimal {
        let calendar = Calendar.current
        let minutesSinceMidnight = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)

        // Find the profile entry that applies at this time of day
        var applicableRate = basalProfile.first?.rate ?? 0
        for entry in basalProfile {
            if entry.minutes <= minutesSinceMidnight {
                applicableRate = entry.rate
            }
        }
        return applicableRate
    }

    // MARK: - State management

    func initializeEmptyState() throws {
        try FileManager.default.createDirectory(
            atPath: stateDir,
            withIntermediateDirectories: true
        )

        let emptyGlucose: [GlucoseRecord] = []
        let emptyPumpEvents: [PumpEventRecord] = []
        let emptyCarbs: [CarbRecord] = []
        let emptyTDD: [TDDRecord] = []

        try saveFast(emptyGlucose, to: glucosePath)
        try saveFast(emptyPumpEvents, to: pumpHistoryPath)
        try saveFast(emptyCarbs, to: carbsPath)
        try saveFast(emptyTDD, to: tddPath)
    }

    func saveAutosens(_ autosens: Autosens) throws {
        try save(autosens, to: autosensPath)
    }

    func loadAutosens() throws -> Autosens {
        try load(Autosens.self, from: autosensPath)
    }

    func saveProfile(_ profile: Profile) throws {
        try save(profile, to: profilePath)
    }

    func loadProfile() throws -> Profile {
        try load(Profile.self, from: profilePath)
    }

    func saveSettings(_ settings: MakeProfileInputs) throws {
        try save(settings, to: settingsPath)
    }

    func loadSettings() throws -> MakeProfileInputs {
        try load(MakeProfileInputs.self, from: settingsPath)
    }

    // MARK: - Virtual user support

    private static let virtualUserFiles = [
        "preferences.json",
        "settings.json",
        "bg_targets.json",
        "basal_profile.json",
        "insulin_sensitivities.json",
        "carb_ratios.json",
        "temptargets.json",
    ]

    static func validateVirtualUserDirectory(_ path: String) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw SimulationStorageError.virtualUserDirectoryNotFound(path)
        }
        for file in virtualUserFiles {
            let filePath = "\(path)/\(file)"
            guard fm.fileExists(atPath: filePath) else {
                throw SimulationStorageError.missingVirtualUserFile(file)
            }
        }
    }

    func copyVirtualUserFiles(from virtualUserDir: String) throws {
        let fm = FileManager.default
        for file in Self.virtualUserFiles {
            let src = "\(virtualUserDir)/\(file)"
            let dst = "\(stateDir)/\(file)"
            try fm.copyItem(atPath: src, toPath: dst)
        }
    }

    func loadProfileInputs(clock: Date) throws -> (
        preferences: Preferences,
        pumpSettings: PumpSettings,
        bgTargets: BGTargets,
        basalProfile: [BasalProfileEntry],
        isf: InsulinSensitivities,
        carbRatios: CarbRatios,
        tempTargets: [TempTarget]
    ) {
        let preferences = try load(Preferences.self, from: preferencesPath)
        let pumpSettings = try load(PumpSettings.self, from: pumpSettingsPath)
        let bgTargets = try load(BGTargets.self, from: bgTargetsPath)
        let basalProfile = try load([BasalProfileEntry].self, from: basalProfilePath)
        let isf = try load(InsulinSensitivities.self, from: insulinSensitivitiesPath)
        let carbRatios = try load(CarbRatios.self, from: carbRatiosPath)
        let tempTargets = try load([TempTarget].self, from: tempTargetsPath)
        return (preferences, pumpSettings, bgTargets, basalProfile, isf, carbRatios, tempTargets)
    }
}

enum SimulationStorageError: Error, CustomStringConvertible {
    case virtualUserDirectoryNotFound(String)
    case missingVirtualUserFile(String)

    var description: String {
        switch self {
        case .virtualUserDirectoryNotFound(let path):
            return "Virtual user directory not found: \(path)"
        case .missingVirtualUserFile(let file):
            return "Missing required virtual user file: \(file)"
        }
    }
}
