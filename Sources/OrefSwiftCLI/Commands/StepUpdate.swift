import ArgumentParser
import Foundation

struct StepUpdate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stepUpdate",
        abstract: "Update the algorithm state for each simulation step."
    )

    @Option(name: .shortAndLong, help: "Input file path (use '-' for STDIN)")  var input: String?

    @Option(name: .shortAndLong, help: "Output file path (use '-' for STDOUT)")  var output: String?

    func run() throws {
        // TODO: Implement stepUpdate
        print("stepUpdate: Not yet implemented")
    }
}
