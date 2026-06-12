import ArgumentParser

@main struct OrefSwiftCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "oref-swift",
        abstract: "A command line interface for the Swift implementation of the Oref algorithm.",
        version: "0.1.0",
        subcommands: [
            // Basic algorithm invocation
            MakeProfile.self,
            Meal.self,
            IOB.self,
            AutosensCommand.self,
            DetermineBasal.self,
            // Simulator commands
            Initialize.self,
            StepUpdate.self,
            Calculate.self
        ]
    )
}
