import ArgumentParser
import Foundation
import OrefSwiftAlgorithm
import OrefSwiftModels

// MARK: - Input struct for direct JSON decoding (avoids JSONSerialization precision loss)

struct MakeProfileInputs: Codable {
    let preferences: Preferences
    let pumpSettings: PumpSettings
    let bgTargets: BGTargets
    let basalProfile: [BasalProfileEntry]
    let isf: InsulinSensitivities
    let carbRatios: CarbRatios
    let tempTargets: [TempTarget]
    let model: String
    let trioSettings: TrioSettings
    let clock: Date

    private enum CodingKeys: String, CodingKey {
        case preferences
        case pumpSettings
        case bgTargets
        case basalProfile
        case isf
        case carbRatios
        case tempTargets
        case model
        case trioSettings
        case clock
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        preferences = try container.decode(Preferences.self, forKey: .preferences)
        pumpSettings = try container.decode(PumpSettings.self, forKey: .pumpSettings)
        bgTargets = try container.decode(BGTargets.self, forKey: .bgTargets)
        basalProfile = try container.decode([BasalProfileEntry].self, forKey: .basalProfile)
        isf = try container.decode(InsulinSensitivities.self, forKey: .isf)
        carbRatios = try container.decode(CarbRatios.self, forKey: .carbRatios)
        tempTargets = try container.decode([TempTarget].self, forKey: .tempTargets)
        trioSettings = try container.decode(TrioSettings.self, forKey: .trioSettings)

        // Handle model which may have quotes or newlines
        let rawModel = try container.decode(String.self, forKey: .model)
        model = rawModel.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

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

// MARK: - MakeProfile Command

struct MakeProfile: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "makeProfile",
        abstract: "Generate an OpenAPS profile from settings."
    )

    @Option(name: .shortAndLong, help: "Input file path (use '-' for STDIN)")  var input: String?

    @Option(name: .shortAndLong, help: "Output file path (use '-' for STDOUT)")  var output: String?

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

        // Decode input directly with JSONDecoder (preserves Decimal precision)
        let profileInput = try JSONCoding.decoder.decode(MakeProfileInputs.self, from: inputData)

        // Generate profile
        let profile = try ProfileGenerator.generate(
            pumpSettings: profileInput.pumpSettings,
            bgTargets: profileInput.bgTargets,
            basalProfile: profileInput.basalProfile,
            isf: profileInput.isf,
            preferences: profileInput.preferences,
            carbRatios: profileInput.carbRatios,
            tempTargets: profileInput.tempTargets,
            model: profileInput.model,
            clock: profileInput.clock
        )

        // Encode output using JSONEncoder directly (matching iOS approach)
        let outputData = try JSONCoding.encoder.encode(profile)

        // Write output
        if let outputPath = output, outputPath != "-" {
            let url = URL(fileURLWithPath: outputPath)
            try outputData.write(to: url)
        } else {
            // Write to stdout
            if let outputString = String(data: outputData, encoding: .utf8) {
                print(outputString)
            }
        }
    }
}
