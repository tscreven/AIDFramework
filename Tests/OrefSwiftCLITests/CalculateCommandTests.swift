import Foundation
import Testing
@testable import OrefSwiftCLI
import OrefSwiftModels

@Suite("Calculate inspection gating")
struct CalculateCommandTests {
    @Test("parseInspectFrom accepts unix timestamps")
    func parseUnixTimestamp() throws {
        let date = try #require(try Calculate.parseInspectFrom("1707800400"))
        #expect(date.timeIntervalSince1970 == 1_707_800_400)
    }

    @Test("parseInspectFrom accepts ISO8601")
    func parseISO8601() throws {
        let date = try #require(try Calculate.parseInspectFrom("2026-03-25T10:15:00Z"))
        let expected = try #require(Formatter.iso8601.date(from: "2026-03-25T10:15:00Z"))
        #expect(date == expected)
    }

    @Test("replay synthesizes current glucose when history is empty")
    func replaySynthesizesCurrentGlucose() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let history = Calculate.glucoseHistory(from: [], currentGlucose: 123, at: now, replay: true)

        #expect(history.count == 1)
        #expect(history[0].sgv == 123)
        #expect(history[0].glucose == 123)
        #expect(history[0].dateString == now)
        #expect(history[0].direction == .flat)
    }

    @Test("replay does not duplicate current glucose when it already exists")
    func replayDoesNotDuplicateCurrentGlucose() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = BloodGlucose(
            _id: "existing",
            sgv: 123,
            direction: .flat,
            date: Decimal(now.timeIntervalSince1970 * 1000),
            dateString: now,
            noise: 0,
            glucose: 123
        )

        let history = Calculate.glucoseHistory(from: [existing], currentGlucose: 123, at: now, replay: true)
        #expect(history.count == 1)
        #expect(history[0]._id == "existing")
    }

    @Test("replay TDD filtering drops future records")
    func replayTDDFilteringDropsFutureRecords() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = TDDRecord(timestamp: now.addingTimeInterval(-300), total: 10)
        let future = TDDRecord(timestamp: now.addingTimeInterval(300), total: 20)

        let filtered = Calculate.filteredReplayTDDRecords([past, future], at: now)
        #expect(filtered.count == 1)
        #expect(filtered[0].total == 10)
    }
}
