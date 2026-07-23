import ArgumentParser
import Foundation
import OrefSwiftAlgorithm
import OrefSwiftModels
import JavaScriptCore


// MARK: - Input struct for direct JSON decoding (avoids JSONSerialization precision loss)

struct IobInputs: Decodable {
    let history: [PumpHistoryEvent]
    let profile: Profile
    let clock: Date
    let autosens: Autosens?

    private enum CodingKeys: String, CodingKey {
        case history
        case profile
        case clock
        case autosens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        history = try container.decode([PumpHistoryEvent].self, forKey: .history)
        profile = try container.decode(Profile.self, forKey: .profile)
        autosens = try container.decodeIfPresent(Autosens.self, forKey: .autosens)

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

// MARK: - IOB Command

struct IOB: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iob",
        abstract: "Calculate insulin on board (IOB)."
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

            let source: String = try loadSourceAlgorithm(js, jsbug, jsiobfix, jsiob_as_fix, jsiob_as_db_fix)
            let jsResultJSONString = try JavaScriptCommandRunner(lib: source).runIOB(inputJSON: inputJSONString)
            let jsData = Data(jsResultJSONString.utf8)

            let outputData: Data
            if let jsDecoded = try? JSONCoding.decoder.decode([IobResult].self, from: jsData) {
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
        let iobInput = try JSONCoding.decoder.decode(IobInputs.self, from: inputData)

        // Generate IOB
        let iobResult = try IobGenerator.generate(
            history: iobInput.history,
            profile: iobInput.profile,
            clock: iobInput.clock,
            autosens: iobInput.autosens
        )

        // Encode output using JSONEncoder directly
        let outputData = try JSONCoding.encoder.encode(iobResult)

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
