import ArgumentParser
import Foundation
import OrefSwiftAlgorithm
import OrefSwiftModels
import JavaScriptCore

// MARK: - Input struct for direct JSON decoding

struct AutosensInputs: Decodable {
    let glucose: [BloodGlucose]
    let history: [PumpHistoryEvent]
    let basalProfile: [BasalProfileEntry]
    let profile: Profile
    let carbs: [CarbsEntry]
    let tempTargets: [TempTarget]
    let clock: Date

    private enum CodingKeys: String, CodingKey {
        case glucose
        case history
        case basalProfile
        case profile
        case carbs
        case tempTargets
        case clock
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        glucose = try container.decode([BloodGlucose].self, forKey: .glucose)
        history = try container.decode([PumpHistoryEvent].self, forKey: .history)
        basalProfile = try container.decode([BasalProfileEntry].self, forKey: .basalProfile)
        profile = try container.decode(Profile.self, forKey: .profile)
        carbs = try container.decode([CarbsEntry].self, forKey: .carbs)
        tempTargets = try container.decode([TempTarget].self, forKey: .tempTargets)

        // Handle clock as either timestamp number or ISO8601 string
        if let timestamp = try? container.decode(Double.self, forKey: .clock) {
            clock = Date(timeIntervalSince1970: timestamp)
        } else if let dateString = try? container.decode(String.self, forKey: .clock) {
            if let date = Formatter.iso8601withFractionalSeconds.date(from: dateString) ??
                Formatter.iso8601.date(from: dateString)
            {
                clock = date
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .clock,
                    in: container,
                    debugDescription: "Invalid date format"
                )
            }
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .clock,
                in: container,
                debugDescription: "Expected number or string for clock"
            )
        }
    }
}

// MARK: - Autosens Command

struct AutosensCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "autosens",
        abstract: "Calculate autosensitivity ratio."
    )

    @Option(name: .shortAndLong, help: "Input file path (use '-' for STDIN)")  var input: String?

    @Option(name: .shortAndLong, help: "Output file path (use '-' for STDOUT)")  var output: String?

    @Flag(name: .long, help: "Replay mode: do not write command outputs to files") var replay: Bool = false
    @Flag(name: .long, help: "Run JavaScript autosens implementation instead of Swift") var js: Bool = false
    @Flag(name: .long, help: "Run buggy JavaScript autosens implementation instead of Swift") var jsbug: Bool = false
    @Flag(name: .long, help: "Run IOB fixed buggy JavaScript autosens implementation instead of Swift") var jsiobfix: Bool = false
    @Flag(name: .long, help: "Run IOB and Autosens fixed buggy JavaScript oref algorithms instead of Swift") var jsiob_as_fix: Bool = false
    @Flag(name: .long, help: "Run IOB, Autosens, and determine basal fixed buggy JavaScript oref algorithms instead of Swift") var jsiob_as_db_fix: Bool = false

    func run() throws {
        // Read input
        let inputData: Data
        if let inputPath: String = input, inputPath != "-" {
            let url: URL = URL(fileURLWithPath: inputPath)
            inputData = try Data(contentsOf: url)
        } else {
            inputData = FileHandle.standardInput.readDataToEndOfFile()
        }

        let runningJS: Bool = js || jsbug || jsiobfix || jsiob_as_fix || jsiob_as_db_fix
        if runningJS {
            guard let inputJSONString = String(data: inputData, encoding: .utf8) else {
                throw JSErrors.invalidUTF8Input
            }

            let source: String = try loadSourceAlgorithm(jsbug, jsiobfix, jsiob_as_fix, jsiob_as_db_fix)
            let jsResultJSONString = try JavaScriptCommandRunner(lib: source).runAutosens(inputJSON: inputJSONString)
            let jsData = Data(jsResultJSONString.utf8)

            let outputData: Data
            if let jsDecoded = try? JSONCoding.decoder.decode(Autosens.self, from: jsData) {
                outputData = try JSONCoding.encoder.encode(jsDecoded)
            } else if let jsonObject = try? JSONSerialization.jsonObject(with: jsData),
                      JSONSerialization.isValidJSONObject(jsonObject)
            {
                outputData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
            } else {
                outputData = jsData
            }

            try writeOutput(outputData)
            return
        }

        // Decode input
        let autosensInput: AutosensInputs = try JSONCoding.decoder.decode(AutosensInputs.self, from: inputData)

        // Generate autosens with 8h window (96 deviations)
        let ratio8h: Autosens = try AutosensGenerator.generate(
            glucose: autosensInput.glucose,
            pumpHistory: autosensInput.history,
            basalProfile: autosensInput.basalProfile,
            profile: autosensInput.profile,
            carbs: autosensInput.carbs,
            tempTargets: autosensInput.tempTargets,
            maxDeviations: 96,
            clock: autosensInput.clock
        )

        // Generate autosens with 24h window (288 deviations)
        let ratio24h: Autosens = try AutosensGenerator.generate(
            glucose: autosensInput.glucose,
            pumpHistory: autosensInput.history,
            basalProfile: autosensInput.basalProfile,
            profile: autosensInput.profile,
            carbs: autosensInput.carbs,
            tempTargets: autosensInput.tempTargets,
            maxDeviations: 288,
            clock: autosensInput.clock
        )

        // Take the lower ratio
        let result: Autosens = ratio8h.ratio < ratio24h.ratio ? ratio8h : ratio24h

        // Encode output
        let outputData: Data = try JSONCoding.encoder.encode(result)

        try writeOutput(outputData)
    }

    private func writeOutput(_ data: Data) throws {
        if let outputPath: String = output, outputPath != "-" {
            if replay { return }
            try data.write(to: URL(fileURLWithPath: outputPath))
        } else {
            if let outputString: String = String(data: data, encoding: .utf8) {
                print(outputString)
            }
        }
    }
}
