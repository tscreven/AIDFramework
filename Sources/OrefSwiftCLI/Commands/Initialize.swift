import ArgumentParser
import Foundation
import OrefSwiftAlgorithm
import OrefSwiftModels

struct InitializeOutput: Encodable {
    let stateDir: String
}

struct Initialize: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "initialize",
        abstract: "Start a new simulator session with the given parameters."
    )

    @Option(name: [.customShort("u"), .long], help: "Path to virtual user directory")
    var virtualUser: String

    @Option(name: .shortAndLong, help: "Output file path (use '-' for STDOUT)")
    var output: String?

    func run() throws {
        // Validate virtual user directory
        try SimulationStorage.validateVirtualUserDirectory(virtualUser)

        // Derive user name from directory path
        let userName = URL(fileURLWithPath: virtualUser).lastPathComponent

        // Generate timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())

        // Create state directory path
        let stateDir = "state/\(userName)_\(timestamp)"
        let storage = SimulationStorage(stateDir: stateDir)

        // Initialize empty state (creates dir + empty glucose, pump_history, carbs)
        try storage.initializeEmptyState()

        // Copy virtual user therapy settings files
        try storage.copyVirtualUserFiles(from: virtualUser)

        // Load therapy settings and generate initial profile
        let now = Date()
        let inputs = try storage.loadProfileInputs(clock: now)

        let model = "722"
        let profile = try ProfileGenerator.generate(
            pumpSettings: inputs.pumpSettings,
            bgTargets: inputs.bgTargets,
            basalProfile: inputs.basalProfile,
            isf: inputs.isf,
            preferences: inputs.preferences,
            carbRatios: inputs.carbRatios,
            tempTargets: inputs.tempTargets,
            model: model,
            clock: now
        )

        // Save initial autosens (default ratio 1.0) and profile
        let autosens = Autosens(ratio: 1.0)
        try storage.saveAutosens(autosens)
        try storage.saveProfile(profile)

        // Output result
        let result = InitializeOutput(stateDir: stateDir)
        let outputData = try JSONCoding.encoder.encode(result)

        if let outputPath = output, outputPath != "-" {
            try outputData.write(to: URL(fileURLWithPath: outputPath))
        } else {
            if let outputString = String(data: outputData, encoding: .utf8) {
                print(outputString)
            }
        }
    }
}
