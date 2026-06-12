import Foundation
import Testing
@testable import OrefSwiftCLI
import OrefSwiftModels

// Use whole-second epoch dates so they round-trip cleanly through ISO8601 JSON encoding.
private let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

private func makeStorage() throws -> SimulationStorage {
    let dir = NSTemporaryDirectory() + "sim_test_\(UUID().uuidString)"
    let storage = SimulationStorage(stateDir: dir)
    try storage.initializeEmptyState()
    return storage
}

private func cleanup(_ storage: SimulationStorage) {
    try? FileManager.default.removeItem(atPath: storage.stateDir)
}

// MARK: - Glucose tests

@Suite("SimulationStorage — Glucose", .serialized)
struct GlucoseStorageTests {
    @Test("store and fetch a single glucose reading")
    func storeSingle() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeGlucose(at: baseTime, glucose: 120)

        let results = storage.fetchGlucose(at: baseTime)
        #expect(results.count == 1)
        #expect(results[0].sgv == 120)
        #expect(results[0].glucose == 120)
        #expect(results[0].noise == 0)
        #expect(results[0].direction == .flat)
    }

    @Test("fetch returns newest first")
    func newestFirst() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeGlucose(at: baseTime.addingTimeInterval(-600), glucose: 100)
        try storage.storeGlucose(at: baseTime.addingTimeInterval(-300), glucose: 110)
        try storage.storeGlucose(at: baseTime, glucose: 120)

        let results = storage.fetchGlucose(at: baseTime)
        #expect(results.count == 3)
        #expect(results[0].sgv == 120)
        #expect(results[1].sgv == 110)
        #expect(results[2].sgv == 100)
    }

    @Test("fetch respects limit")
    func limit() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        for i in 0 ..< 10 {
            try storage.storeGlucose(
                at: baseTime.addingTimeInterval(Double(i) * 300),
                glucose: Decimal(100 + i)
            )
        }

        let fetchTime = baseTime.addingTimeInterval(Double(9) * 300)
        let results = storage.fetchGlucose(at: fetchTime, limit: 3)
        #expect(results.count == 3)
        // Should be the 3 most recent (newest first)
        #expect(results[0].sgv == 109)
        #expect(results[1].sgv == 108)
        #expect(results[2].sgv == 107)
    }

    @Test("fetch filters out readings older than 24 hours")
    func twentyFourHourWindow() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeGlucose(at: baseTime.addingTimeInterval(-25 * 3600), glucose: 80)
        try storage.storeGlucose(at: baseTime.addingTimeInterval(-23 * 3600), glucose: 90)
        try storage.storeGlucose(at: baseTime, glucose: 100)

        let results = storage.fetchGlucose(at: baseTime)
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.sgv != 80 })
    }

    @Test("fetch excludes future readings")
    func excludesFuture() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeGlucose(at: baseTime, glucose: 100)
        try storage.storeGlucose(at: baseTime.addingTimeInterval(300), glucose: 200)

        let results = storage.fetchGlucose(at: baseTime)
        #expect(results.count == 1)
        #expect(results[0].sgv == 100)
    }

    @Test("direction is computed from consecutive readings")
    func directionComputation() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeGlucose(at: baseTime.addingTimeInterval(-300), glucose: 100)
        try storage.storeGlucose(at: baseTime, glucose: 120) // delta = +20

        let results = storage.fetchGlucose(at: baseTime)
        #expect(results[0].direction == .tripleUp)  // 120 - 100 = 20 > 17
        #expect(results[1].direction == .flat)        // no previous reading
    }

    @Test("date field is milliseconds since epoch")
    func dateMilliseconds() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeGlucose(at: baseTime, glucose: 100)

        let results = storage.fetchGlucose(at: baseTime)
        let expectedMs = Decimal(baseTime.timeIntervalSince1970 * 1000)
        #expect(results[0].date == expectedMs)
    }

    @Test("fetch from empty store returns empty array")
    func emptyFetch() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        let results = storage.fetchGlucose(at: baseTime)
        #expect(results.isEmpty)
    }
}

// MARK: - Pump event tests

@Suite("SimulationStorage — Pump Events", .serialized)
struct PumpEventStorageTests {
    @Test("store and fetch temp basal expands into two events")
    func tempBasalExpansion() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeTempBasal(at: baseTime, rate: 1.5, duration: 30)

        let events = storage.fetchPumpEvents(at: baseTime)
        #expect(events.count == 2)

        let durationEvent = events.first { $0.type == .tempBasalDuration }
        let rateEvent = events.first { $0.type == .tempBasal }

        #expect(durationEvent != nil)
        #expect(rateEvent != nil)
        #expect(durationEvent?.durationMin == 30)
        #expect(rateEvent?.rate == 1.5)
        #expect(rateEvent?.temp == .absolute)
    }

    @Test("temp basal rate event id is prefixed with underscore")
    func tempBasalIdPrefix() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeTempBasal(at: baseTime, rate: 1.0, duration: 30)

        let events = storage.fetchPumpEvents(at: baseTime)
        let durationEvent = events.first { $0.type == .tempBasalDuration }!
        let rateEvent = events.first { $0.type == .tempBasal }!

        #expect(rateEvent.id == "_\(durationEvent.id)")
    }

    @Test("store and fetch SMB produces single bolus event")
    func smbEvent() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeSMB(at: baseTime, amount: 0.5)

        let events = storage.fetchPumpEvents(at: baseTime)
        #expect(events.count == 1)
        #expect(events[0].type == .bolus)
        #expect(events[0].amount == 0.5)
        #expect(events[0].isSMB == true)
    }

    @Test("fetch pump events filters 24-hour window")
    func pumpEvents24HourWindow() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeTempBasal(at: baseTime.addingTimeInterval(-25 * 3600), rate: 1.0, duration: 30)
        try storage.storeSMB(at: baseTime, amount: 0.3)

        let events = storage.fetchPumpEvents(at: baseTime)
        #expect(events.count == 1)
        #expect(events[0].type == .bolus)
    }

    @Test("mixed temp basals and SMBs returned together")
    func mixedEvents() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeTempBasal(at: baseTime.addingTimeInterval(-600), rate: 2.0, duration: 30)
        try storage.storeSMB(at: baseTime, amount: 0.1)

        let events = storage.fetchPumpEvents(at: baseTime)
        // 2 from temp basal + 1 from SMB
        #expect(events.count == 3)
    }

    @Test("fetch pump events from empty store returns empty array")
    func emptyPumpFetch() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        let events = storage.fetchPumpEvents(at: baseTime)
        #expect(events.isEmpty)
    }
}

// MARK: - Current temp basal tests

@Suite("SimulationStorage — Current Temp Basal", .serialized)
struct CurrentTempBasalTests {
    @Test("returns default when no temp basal exists")
    func defaultWhenEmpty() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        let result = storage.fetchCurrentTempBasal(at: baseTime)
        #expect(result.duration == 0)
        #expect(result.rate == 0)
        #expect(result.temp == .absolute)
    }

    @Test("returns remaining duration for active temp basal")
    func remainingDuration() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        // Temp basal started 10 minutes ago with 30-minute duration
        try storage.storeTempBasal(at: baseTime.addingTimeInterval(-600), rate: 2.0, duration: 30)

        let result = storage.fetchCurrentTempBasal(at: baseTime)
        #expect(result.rate == 2.0)
        #expect(result.duration == 20) // 30 - 10 = 20
        #expect(result.temp == .absolute)
    }

    @Test("returns default when temp basal has expired")
    func expiredTempBasal() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        // Temp basal started 15 minutes ago with 10-minute duration
        try storage.storeTempBasal(at: baseTime.addingTimeInterval(-900), rate: 1.5, duration: 10)

        let result = storage.fetchCurrentTempBasal(at: baseTime)
        #expect(result.duration == 0)
        #expect(result.rate == 0)
    }

    @Test("returns default when temp basal is older than 20 minutes")
    func outsideLookback() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        // Temp basal started 25 minutes ago (outside 20-minute lookback)
        try storage.storeTempBasal(at: baseTime.addingTimeInterval(-1500), rate: 1.0, duration: 60)

        let result = storage.fetchCurrentTempBasal(at: baseTime)
        #expect(result.duration == 0)
        #expect(result.rate == 0)
    }

    @Test("uses most recent temp basal when multiple exist")
    func mostRecent() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeTempBasal(at: baseTime.addingTimeInterval(-900), rate: 1.0, duration: 30)
        try storage.storeTempBasal(at: baseTime.addingTimeInterval(-300), rate: 2.5, duration: 30)

        let result = storage.fetchCurrentTempBasal(at: baseTime)
        #expect(result.rate == 2.5)
        #expect(result.duration == 25) // 30 - 5 = 25
    }

    @Test("ignores SMB events when looking for temp basal")
    func ignoresSMB() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeSMB(at: baseTime.addingTimeInterval(-60), amount: 0.5)

        let result = storage.fetchCurrentTempBasal(at: baseTime)
        #expect(result.duration == 0)
        #expect(result.rate == 0)
    }
}

// MARK: - Carb tests

@Suite("SimulationStorage — Carbs", .serialized)
struct CarbStorageTests {
    @Test("store and fetch carbs")
    func storeAndFetch() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeCarbs(at: baseTime, carbs: 45)

        let results = storage.fetchCarbs(at: baseTime)
        #expect(results.count == 1)
        #expect(results[0].carbs == 45)
        #expect(results[0].isFPU == false)
        #expect(results[0].fat == nil)
        #expect(results[0].protein == nil)
        #expect(results[0].id != nil)
    }

    @Test("fetch carbs filters 24-hour window")
    func carbs24HourWindow() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeCarbs(at: baseTime.addingTimeInterval(-25 * 3600), carbs: 30)
        try storage.storeCarbs(at: baseTime, carbs: 50)

        let results = storage.fetchCarbs(at: baseTime)
        #expect(results.count == 1)
        #expect(results[0].carbs == 50)
    }

    @Test("fetch carbs excludes future entries")
    func excludesFutureCarbs() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeCarbs(at: baseTime, carbs: 20)
        try storage.storeCarbs(at: baseTime.addingTimeInterval(300), carbs: 40)

        let results = storage.fetchCarbs(at: baseTime)
        #expect(results.count == 1)
        #expect(results[0].carbs == 20)
    }

    @Test("fetch carbs from empty store returns empty array")
    func emptyCarbFetch() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        let results = storage.fetchCarbs(at: baseTime)
        #expect(results.isEmpty)
    }

    @Test("multiple carb entries returned")
    func multipleCarbs() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        try storage.storeCarbs(at: baseTime.addingTimeInterval(-3600), carbs: 20)
        try storage.storeCarbs(at: baseTime.addingTimeInterval(-1800), carbs: 30)
        try storage.storeCarbs(at: baseTime, carbs: 10)

        let results = storage.fetchCarbs(at: baseTime)
        #expect(results.count == 3)
    }
}

// MARK: - State management tests

@Suite("SimulationStorage — State Management", .serialized)
struct StateManagementTests {
    @Test("initializeEmptyState creates directory and empty files")
    func initCreatesFiles() throws {
        let dir = NSTemporaryDirectory() + "sim_test_\(UUID().uuidString)"
        let storage = SimulationStorage(stateDir: dir)
        defer { cleanup(storage) }

        try storage.initializeEmptyState()

        #expect(FileManager.default.fileExists(atPath: dir))
        #expect(storage.fetchGlucose(at: baseTime).isEmpty)
        #expect(storage.fetchPumpEvents(at: baseTime).isEmpty)
        #expect(storage.fetchCarbs(at: baseTime).isEmpty)
    }

    @Test("save and load autosens round-trips correctly")
    func autosensRoundTrip() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        let autosens = Autosens(ratio: 1.2, timestamp: baseTime)
        try storage.saveAutosens(autosens)

        let loaded = try storage.loadAutosens()
        #expect(loaded.ratio == 1.2)
    }

    @Test("save and load autosens with default ratio")
    func autosensDefault() throws {
        let storage = try makeStorage()
        defer { cleanup(storage) }

        let autosens = Autosens(ratio: 1.0)
        try storage.saveAutosens(autosens)

        let loaded = try storage.loadAutosens()
        #expect(loaded.ratio == 1.0)
        #expect(loaded.timestamp == nil)
    }

    @Test("calling initializeEmptyState twice does not fail")
    func doubleInit() throws {
        let dir = NSTemporaryDirectory() + "sim_test_\(UUID().uuidString)"
        let storage = SimulationStorage(stateDir: dir)
        defer { cleanup(storage) }

        try storage.initializeEmptyState()
        try storage.initializeEmptyState()

        #expect(storage.fetchGlucose(at: baseTime).isEmpty)
    }
}
