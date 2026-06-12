import ArgumentParser
import Foundation
import OrefSwiftAlgorithm
import OrefSwiftModels

// MARK: - Input struct for direct JSON decoding

struct MealInputs: Decodable {
    let pumpHistory: [PumpHistoryEvent]
    let profile: Profile
    let basalProfile: [BasalProfileEntry]
    let clock: Date
    let carbs: [CarbsEntry]
    let glucose: [BloodGlucose]

    private enum CodingKeys: String, CodingKey {
        case pumpHistory
        case profile
        case basalProfile
        case clock
        case carbs
        case glucose
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        pumpHistory = try container.decode([PumpHistoryEvent].self, forKey: .pumpHistory)
        profile = try container.decode(Profile.self, forKey: .profile)
        basalProfile = try container.decode([BasalProfileEntry].self, forKey: .basalProfile)
        carbs = try container.decode([CarbsEntry].self, forKey: .carbs)
        glucose = try container.decode([BloodGlucose].self, forKey: .glucose)

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

// MARK: - Meal Command

struct Meal: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "meal",
        abstract: "Calculate meal data including carbs on board (COB)."
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
        if let inputPath = input, inputPath != "-" {
            let url = URL(fileURLWithPath: inputPath)
            inputData = try Data(contentsOf: url)
        } else {
            // Read from stdin
            inputData = FileHandle.standardInput.readDataToEndOfFile()
        }

        let runningJS: Bool = js || jsbug || jsiobfix || jsiob_as_fix || jsiob_as_db_fix
        if runningJS {
            guard let inputJSONString = String(data: inputData, encoding: .utf8) else {
                throw JSErrors.invalidUTF8Input
            }

            let source: String = try loadSourceAlgorithm(jsbug, jsiobfix, jsiob_as_fix, jsiob_as_db_fix)
            let jsResultJSONString = try JavaScriptCommandRunner(lib: source).runMeal(inputJSON: inputJSONString)
            let jsData = Data(jsResultJSONString.utf8)

            let outputData: Data
            if let jsDecoded = try? JSONCoding.decoder.decode(ComputedCarbs?.self, from: jsData) {
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

        // Decode input directly with JSONDecoder (preserves Decimal precision)
        let mealInput = try JSONCoding.decoder.decode(MealInputs.self, from: inputData)

        // Generate meal
        let mealResult = try MealGenerator.generate(
            pumpHistory: mealInput.pumpHistory,
            profile: mealInput.profile,
            basalProfile: mealInput.basalProfile,
            clock: mealInput.clock,
            carbHistory: mealInput.carbs,
            glucoseHistory: mealInput.glucose
        )

        // Encode output using JSONEncoder directly
        let outputData: Data
        if let result = mealResult {
            outputData = try JSONCoding.encoder.encode(result)
        } else {
            outputData = "null".data(using: .utf8)!
        }

        try writeOutput(outputData)
    }

    private func writeOutput(_ data: Data) throws {
        if let outputPath = output, outputPath != "-" {
            if replay { return }
            try data.write(to: URL(fileURLWithPath: outputPath))
        } else {
            if let outputString = String(data: data, encoding: .utf8) {
                print(outputString)
            }
        }
    }
}
