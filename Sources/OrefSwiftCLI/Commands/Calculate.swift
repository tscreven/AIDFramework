import ArgumentParser
import Foundation
import OrefSwiftAlgorithm
import OrefSwiftModels

struct CalculateInput: Decodable {
    let timestamp: Double // Unix timestamp (seconds since epoch)
    let glucose: Decimal // mg/dL
}

private struct JSIobInput: Encodable {
    let history: [PumpHistoryEvent]
    let profile: Profile
    let clock: Date
    let autosens: Autosens?
}

private struct JSMealInput: Encodable {
    let pumpHistory: [PumpHistoryEvent]
    let profile: Profile
    let basalProfile: [BasalProfileEntry]
    let clock: Date
    let carbs: [CarbsEntry]
    let glucose: [BloodGlucose]
}

private struct JSDetermineBasalInput: Encodable {
    let glucose: [BloodGlucose]
    let currentTemp: TempBasal
    let iob: [IobResult]
    let profile: Profile
    let autosens: Autosens
    let meal: ComputedCarbs
    let microBolusAllowed: Bool
    let reservoir: Decimal
    let pumpHistory: [PumpHistoryEvent]
    let preferences: Preferences
    let basalProfile: [BasalProfileEntry]
    let trioCustomOrefVariables: TrioCustomOrefVariables
    let clock: Date
}

private struct JSAutosensInput: Encodable {
    let glucose: [BloodGlucose]
    let history: [PumpHistoryEvent]
    let basalProfile: [BasalProfileEntry]
    let profile: Profile
    let carbs: [CarbsEntry]
    let tempTargets: [TempTarget]
    let clock: Date
}

private struct JSAutosensOutput: Decodable {
    let ratio: Decimal
    let newisf: Decimal?
    let deviationsUnsorted: [Decimal]?
    let timestamp: Date?
    let error: String?
}

struct Calculate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calculate",
        abstract: "Calculate insulin dosing for a given algorithm state and new glucose reading."
    )

    @Option(name: [.customShort("s"), .long], help: "Path to simulation state directory")
    var stateDir: String

    @Option(name: .shortAndLong, help: "Input file path (use '-' for STDIN)") var input: String?

    @Option(name: .shortAndLong, help: "Output file path (use '-' for STDOUT)") var output: String?
    @Flag(name: .long, help: "Print per-step timing to stderr") var timing: Bool = false
    @Flag(name: .long, help: "Run JavaScript autosens implementation instead of Swift") var js: Bool = false
    @Flag(name: .long, help: "Run buggy JavaScript autosens implementation instead of Swift") var jsbug: Bool = false
    @Flag(name: .long, help: "Encode autosens JS input dates as Unix seconds (triggers dateString bucket-collapse bug in autosens.js). Default is ISO8601.") var autosensSeconds: Bool = false

    func run() throws {
        let totalStart = DispatchTime.now()
        var timings: [(String, UInt64)] = []
        var jsIobOutput: String?
        var jsMealOutput: String?
        var jsDetermineBasalOutput: String?
        var jsAutosensOutput: String?
        var jsRunner: JavaScriptCommandRunner?

        if js || jsbug {
            let source: String = try loadSourceAlgorithm(js, jsbug)
            jsRunner = try JavaScriptCommandRunner(lib: source)
        }

        func mark(_ label: String, since start: DispatchTime) {
            let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            timings.append((label, elapsed))
        }

        let logPath = "temp.txt"
        let logURL = URL(fileURLWithPath: logPath)
        func appendLog(_ line: String) {
            let data = Data((line + "\n").utf8)
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? (line + "\n").write(to: logURL, atomically: true, encoding: .utf8)
            }
        }

        func jsonString<T: Encodable>(for value: T) throws -> String {
            let data = try JSONCoding.encoder.encode(value)
            return String(decoding: data, as: UTF8.self)
        }

        // Autosens JS input: encode dates as Unix seconds (matching Trio app format).
        // The bug in autosens.js is triggered by `dateString` being a number in seconds —
        // `new Date(1763632148)` treats it as ms → Jan 1970 → corrupts bucketed_data via reference mutation.
        func autosensJSONString<T: Encodable>(for value: T) throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(value)
            return String(decoding: data, as: UTF8.self)
        }

        // 1. Read and decode input
        var stepStart = DispatchTime.now()
        let inputData: Data
        if let inputPath = input, inputPath != "-" {
            let url = URL(fileURLWithPath: inputPath)
            inputData = try Data(contentsOf: url)
        } else {
            inputData = FileHandle.standardInput.readDataToEndOfFile()
        }

        let calcInput = try JSONCoding.decoder.decode(CalculateInput.self, from: inputData)
        let now = Date(timeIntervalSince1970: calcInput.timestamp)
        let storage = SimulationStorage(stateDir: stateDir)
        mark("readInput", since: stepStart)

        // 2. Store glucose
        stepStart = DispatchTime.now()
        try storage.storeGlucose(at: now, glucose: calcInput.glucose)
        mark("storeGlucose", since: stepStart)

        // 3. Regenerate profile
        stepStart = DispatchTime.now()
        let inputs = try storage.loadProfileInputs(clock: now)
        var preferences = inputs.preferences

        let model = "722"
        let profile = try ProfileGenerator.generate(
            pumpSettings: inputs.pumpSettings,
            bgTargets: inputs.bgTargets,
            basalProfile: inputs.basalProfile,
            isf: inputs.isf,
            preferences: preferences,
            carbRatios: inputs.carbRatios,
            tempTargets: inputs.tempTargets,
            model: model,
            clock: now
        )
        try storage.saveProfile(profile)
        mark("makeProfile", since: stepStart)

        // 4. Fetch data
        stepStart = DispatchTime.now()
        let glucoseHistory = Self.glucoseHistory(
            from: storage.fetchGlucose(at: now),
            currentGlucose: calcInput.glucose,
            at: now,
        )
        let pumpEventRecords = storage.loadPumpEventRecords()
        let pumpHistory = storage.fetchPumpEvents(at: now, from: pumpEventRecords)
        let carbHistory = storage.fetchCarbs(at: now)
        let currentTemp = storage.fetchCurrentTempBasal(at: now, from: pumpEventRecords)
        mark("fetchData", since: stepStart)

        // 5. Calculate and store TDD
        stepStart = DispatchTime.now()
        let currentTDD = storage.calculateTDD(at: now, basalProfile: inputs.basalProfile, from: pumpEventRecords)
        mark("tdd.calculate", since: stepStart)

        stepStart = DispatchTime.now()
        let tddRecords: [TDDRecord]
        tddRecords = try storage.storeTDD(at: now, total: currentTDD)
        mark("tdd.store", since: stepStart)

        stepStart = DispatchTime.now()
        let twoHoursAgo = now.addingTimeInterval(-2 * 60 * 60)
        let recentTDDRecords = tddRecords.filter { $0.timestamp > twoHoursAgo }

        let averageTDD = tddRecords.isEmpty ? Decimal(0)
            : tddRecords.map(\.total).reduce(0, +) / Decimal(tddRecords.count)
        let past2hoursAverage = recentTDDRecords.isEmpty ? Decimal(0)
            : recentTDDRecords.map(\.total).reduce(0, +) / Decimal(recentTDDRecords.count)

        let weightPercentage = preferences.weightPercentage
        let weightedAverage: Decimal
        if !recentTDDRecords.isEmpty, !tddRecords.isEmpty {
            weightedAverage = weightPercentage * past2hoursAverage + (1 - weightPercentage) * averageTDD
        } else {
            weightedAverage = currentTDD
        }

        // Disable TDD features if insufficient data (need >=75% of expected 5-min points over 7 days)
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let weekRecords = tddRecords.filter { $0.timestamp > sevenDaysAgo }
        let sufficientTDD = weekRecords.count >= Int(Double(7 * 288) * 0.75) // 1512 data points
        if !sufficientTDD {
            preferences.useNewFormula = false
            preferences.sigmoid = false
        }
        mark("tdd.averages", since: stepStart)

        // 6. Autosens check — recalculate if stale (>30 min) or missing, and enough data
        stepStart = DispatchTime.now()
        var autosens = try storage.loadAutosens()
        let autosensAge: TimeInterval    
        if let autosensTimestamp = autosens.timestamp {
            autosensAge = now.timeIntervalSince(autosensTimestamp)
        } else {
            autosensAge = .infinity
        }

        if autosensAge > 30 * 60, glucoseHistory.count >= 72 {
            if let jsRunner {
                appendLog("autosens-dbg: RECALC via JS autosensSeconds=\(autosensSeconds) clock=\(now)")
                let autosensInput = JSAutosensInput(
                    glucose: glucoseHistory,
                    history: pumpHistory,
                    basalProfile: inputs.basalProfile,
                    profile: profile,
                    carbs: carbHistory,
                    tempTargets: inputs.tempTargets,
                    clock: now
                )
                let autosensInputJSON = autosensSeconds
                    ? (try autosensJSONString(for: autosensInput))
                    : (try jsonString(for: autosensInput))
                // jsbug: let JS find_insulin run natively (reproduces 8h-window IOB bug → ratio=1)
                // all other JS modes: inject Swift IOB so autosens deviations are correct
                jsAutosensOutput = try jsRunner.runAutosens(inputJSON: autosensInputJSON, injectSwiftIOB: !jsbug)
                guard let jsAutosensOutput,
                      let jsAutosensData = jsAutosensOutput.data(using: .utf8)
                else {
                    throw JSErrors.missingJSResult
                }
                autosens = try decodeJSAutosens(from: jsAutosensData)
                appendLog("autosens-dbg: RECALC via JS result ratio=\(autosens.ratio) newisf=\(autosens.newisf ?? 0) clock=\(now)")
            } else {
                appendLog("autosens-dbg: RECALC via Swift clock=\(now)")
                let ratio8h = try AutosensGenerator.generate(
                    glucose: glucoseHistory,
                    pumpHistory: pumpHistory,
                    basalProfile: inputs.basalProfile,
                    profile: profile,
                    carbs: carbHistory,
                    tempTargets: inputs.tempTargets,
                    maxDeviations: 96,
                    clock: now,
                    includeDeviationsForTesting: true
                )

                let ratio24h = try AutosensGenerator.generate(
                    glucose: glucoseHistory,
                    pumpHistory: pumpHistory,
                    basalProfile: inputs.basalProfile,
                    profile: profile,
                    carbs: carbHistory,
                    tempTargets: inputs.tempTargets,
                    maxDeviations: 288,
                    clock: now,
                    includeDeviationsForTesting: true
                )

                appendLog("autosens-dbg: RECALC via Swift result 8h ratio=\(ratio8h.ratio) 24h ratio=\(ratio24h.ratio) clock=\(now)")
                autosens = ratio8h.ratio < ratio24h.ratio ? ratio8h : ratio24h
                if let debugInfo = autosens.debugInfo {
                    let fmt = ISO8601DateFormatter()
                    for d in debugInfo {
                        appendLog("[autosens-deviation-swift] t=\(fmt.string(from: d.iobClock)) bgi=\(d.bgi) delta=\(d.deltaGlucose) deviation=\(d.deviation) mealCOB=\(d.mealCOB ?? 0) state=\(d.stateType)")
                    }
                }
            }
            autosens.timestamp = now
            try storage.saveAutosens(autosens)
        }
        mark("autosens", since: stepStart)

        // Per-step autosens log
        let autosensAgeMinForLog = autosensAge.isInfinite ? "inf" : String(format: "%.1f", autosensAge / 60.0)
        appendLog("autosens: ratio=\(autosens.ratio) newisf=\(autosens.newisf ?? 0) age=\(autosensAgeMinForLog)min glucoseCount=\(glucoseHistory.count) clock=\(now)")

        // 7. Run IOB
        stepStart = DispatchTime.now()
        let iobData: [IobResult]
        if let jsRunner {
            let iobInput = JSIobInput(history: pumpHistory, profile: profile, clock: now, autosens: autosens)
            jsIobOutput = try jsRunner.runIOB(inputJSON: try jsonString(for: iobInput))
            guard let jsIobOutput,
                  let jsIobData = jsIobOutput.data(using: .utf8)
            else {
                throw JSErrors.missingJSResult
            }
            iobData = try JSONCoding.decoder.decode([IobResult].self, from: jsIobData)
        } else {
            iobData = try IobGenerator.generate(
                history: pumpHistory,
                profile: profile,
                clock: now,
                autosens: autosens
            )
        }
        mark("iob", since: stepStart)

        // 8. Run Meal
        stepStart = DispatchTime.now()
        let mealData: ComputedCarbs?
        if let jsRunner {
            let mealInput = JSMealInput(
                pumpHistory: pumpHistory,
                profile: profile,
                basalProfile: inputs.basalProfile,
                clock: now,
                carbs: carbHistory,
                glucose: glucoseHistory
            )
            jsMealOutput = try jsRunner.runMeal(inputJSON: try jsonString(for: mealInput))
            guard let jsMealOutput,
                  let jsMealData = jsMealOutput.data(using: .utf8)
            else {
                throw JSErrors.missingJSResult
            }
            mealData = try JSONCoding.decoder.decode(ComputedCarbs?.self, from: jsMealData)
        } else {
            mealData = try MealGenerator.generate(
                pumpHistory: pumpHistory,
                profile: profile,
                basalProfile: inputs.basalProfile,
                clock: now,
                carbHistory: carbHistory,
                glucoseHistory: glucoseHistory
            )
        }
        mark("meal", since: stepStart)

        // 9. Construct TrioCustomOrefVariables with TDD data
        let trioVars = TrioCustomOrefVariables(
            average_total_data: currentTDD > 0 ? averageTDD : 0,
            weightedAverage: currentTDD > 0 ? weightedAverage : 1,
            currentTDD: currentTDD,
            past2hoursAverage: currentTDD > 0 ? past2hoursAverage : 0,
            date: now,
            overridePercentage: 100,
            useOverride: false,
            duration: 0,
            unlimited: false,
            overrideTarget: 0,
            smbIsOff: false,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: preferences.maxSMBBasalMinutes,
            uamMinutes: preferences.maxUAMSMBBasalMinutes
        )

        // 10. Run determineBasal
        stepStart = DispatchTime.now()
        let outputData: Data
        var determinationForStorage: Determination?
        do {
            guard let meal = mealData else {
                outputData = "null".data(using: .utf8)!
                return writeOutput(outputData)
            }

            if let jsRunner {
                let determineBasalInput = JSDetermineBasalInput(
                    glucose: glucoseHistory,
                    currentTemp: currentTemp,
                    iob: iobData,
                    profile: profile,
                    autosens: autosens,
                    meal: meal,
                    microBolusAllowed: true,
                    reservoir: 100,
                    pumpHistory: pumpHistory,
                    preferences: preferences,
                    basalProfile: inputs.basalProfile,
                    trioCustomOrefVariables: trioVars,
                    clock: now
                )
                jsDetermineBasalOutput = try jsRunner.runDetermineBasal(inputJSON: try jsonString(for: determineBasalInput))
                guard let jsDetermineBasalOutput,
                      let jsDetermineData = jsDetermineBasalOutput.data(using: .utf8)
                else {
                    throw JSErrors.missingJSResult
                }
                if let determination = try? JSONCoding.decoder.decode(Determination.self, from: jsDetermineData) {
                    determinationForStorage = determination
                    outputData = try JSONCoding.encoder.encode(determination)
                } else if let determinationError = try? JSONCoding.decoder.decode(DeterminationErrorResponse.self, from: jsDetermineData) {
                    outputData = try JSONCoding.encoder.encode(determinationError)
                } else {
                    outputData = jsDetermineData
                }
            } else {
                let result = try DeterminationGenerator.generate(
                    profile: profile,
                    preferences: preferences,
                    currentTemp: currentTemp,
                    iobData: iobData,
                    mealData: meal,
                    autosensData: autosens,
                    reservoirData: 100,
                    glucose: glucoseHistory,
                    microBolusAllowed: true,
                    trioCustomOrefVariables: trioVars,
                    currentTime: now
                )

                determinationForStorage = result

                if let determination = result {
                    outputData = try JSONCoding.encoder.encode(determination)
                } else {
                    outputData = "null".data(using: .utf8)!
                }
            }

        } catch let determinationError as DeterminationError {
            let errorResponse = DeterminationErrorResponse(error: determinationError.localizedDescription)
            outputData = try JSONCoding.encoder.encode(errorResponse)
        }

        // Per-step determine-basal log
        if let det = determinationForStorage {
            let sensRatio = det.sensitivityRatio ?? autosens.ratio
            let mode = jsbug ? "jsbug" : (js ? "js" : "swift")
            appendLog("determine-basal: mode=\(mode) sensitivityRatio=\(sensRatio) autosens.ratio=\(autosens.ratio) dynamicISF=\(preferences.useNewFormula) sufficientTDD=\(sufficientTDD) clock=\(now)")
            let iobCurrent = iobData.first?.iob ?? 0
            let rateStr = det.rate.map { "\($0)" } ?? "nil"
            let unitsStr = det.units.map { "\($0)" } ?? "nil"
            let isfStr = det.isf.map { "\($0)" } ?? "nil"
            let eventualBGStr = det.eventualBG.map { "\($0)" } ?? "nil"
            let bgStr = det.bg.map { "\($0)" } ?? "nil"
            let insulinReqStr = det.insulinReq.map { "\($0)" } ?? "nil"
            appendLog("determination: mode=\(mode) bg=\(bgStr) iob=\(iobCurrent) eventualBG=\(eventualBGStr) rate=\(rateStr) units=\(unitsStr) insulinReq=\(insulinReqStr) isf=\(isfStr) clock=\(now)")
        }

        // 11. Store pump events
        if let determination = determinationForStorage {
            if determination.rate != nil, let duration = determination.duration {
                try storage.storeTempBasal(at: now, rate: determination.rate!, duration: Int(truncating: duration as NSDecimalNumber))
            }
            if let units = determination.units, units > 0 {
                try storage.storeSMB(at: now, amount: units)
            }
        }
        mark("determineBasal", since: stepStart)

        // 12. Save determination to determinations directory
        stepStart = DispatchTime.now()

        let determinationsDir = "\(stateDir)/determinations"
        try FileManager.default.createDirectory(atPath: determinationsDir, withIntermediateDirectories: true)
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime]
        timestampFormatter.timeZone = TimeZone.current
        let timestampString = timestampFormatter.string(from: now)
        try outputData.write(to: URL(fileURLWithPath: "\(determinationsDir)/\(timestampString).json"))

        if js || jsbug {
            let jsDir: String = "\(stateDir)/js_comparisons/\(timestampString)"
            try FileManager.default.createDirectory(atPath: jsDir, withIntermediateDirectories: true)
            if let jsIobOutput {
                try Data(jsIobOutput.utf8).write(to: URL(fileURLWithPath: "\(jsDir)/js_iob.json"))
            }
            if let jsMealOutput {
                try Data(jsMealOutput.utf8).write(to: URL(fileURLWithPath: "\(jsDir)/js_meal.json"))
            }
            if let jsDetermineBasalOutput {
                try Data(jsDetermineBasalOutput.utf8).write(to: URL(fileURLWithPath: "\(jsDir)/js_determine_basal.json"))
            }
            if let jsAutosensOutput {
                try Data(jsAutosensOutput.utf8).write(to: URL(fileURLWithPath: "\(jsDir)/js_autosens.json"))
            }
        }

        mark("saveState", since: stepStart)

        // 13. Output
        writeOutput(outputData)

        // Print timing summary to stderr if --timing flag is set
        if timing {
            let totalElapsed = DispatchTime.now().uptimeNanoseconds - totalStart.uptimeNanoseconds
            for (label, ns) in timings {
                let ms = Double(ns) / 1_000_000
                FileHandle.standardError.write("[timing] \(label): \(String(format: "%.1f", ms))ms\n".data(using: .utf8)!)
            }
            let totalMs = Double(totalElapsed) / 1_000_000
            FileHandle.standardError.write("[timing] TOTAL: \(String(format: "%.1f", totalMs))ms\n".data(using: .utf8)!)
        }
    }

    private func writeOutput(_ data: Data) {
        if let outputPath = output, outputPath != "-" {
            try? data.write(to: URL(fileURLWithPath: outputPath))
        } else {
            if let outputString = String(data: data, encoding: .utf8) {
                print(outputString)
            }
        }
    }

    private func decodeJSAutosens(from data: Data) throws -> Autosens {
        if let autosens = try? JSONCoding.decoder.decode(Autosens.self, from: data) {
            return autosens
        }

        let jsAutosens = try JSONCoding.decoder.decode(JSAutosensOutput.self, from: data)
        return Autosens(
            ratio: jsAutosens.ratio,
            newisf: jsAutosens.newisf,
            deviationsUnsorted: jsAutosens.deviationsUnsorted,
            timestamp: jsAutosens.timestamp,
            debugInfo: nil,
            error: jsAutosens.error
        )
    }

    static func glucoseHistory(
        from storedHistory: [BloodGlucose],
        currentGlucose: Decimal,
        at timestamp: Date,
    ) -> [BloodGlucose] {
        guard storedHistory.first?.dateString != timestamp else { return storedHistory }

        let currentSgv = NSDecimalNumber(decimal: currentGlucose).intValue
        let nextSgv = storedHistory.first?.sgv ?? storedHistory.first?.glucose
        let direction = nextSgv.map { DirectionCalculator.direction(from: currentSgv - $0) } ?? .flat

        let currentReading = BloodGlucose(
            _id: UUID().uuidString,
            sgv: currentSgv,
            direction: direction,
            date: Decimal(timestamp.timeIntervalSince1970 * 1000),
            dateString: timestamp,
            noise: 0,
            glucose: currentSgv
        )

        return [currentReading] + storedHistory
    }
}
