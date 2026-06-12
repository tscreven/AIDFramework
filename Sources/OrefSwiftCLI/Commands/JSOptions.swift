import ArgumentParser

struct JSOptions: ParsableArguments {
    @Flag(name: .long, help: "Replay mode: do not write command outputs to files")
    var replay: Bool = false

    @Flag(name: .long, help: "Run JavaScript autosens implementation instead of Swift")
    var js: Bool = false

    @Flag(name: .long, help: "Run buggy JavaScript autosens implementation instead of Swift")
    var jsbug: Bool = false

    @Flag(name: .long, help: "Run IOB fixed buggy JavaScript autosens implementation instead of Swift")
    var jsiobfix: Bool = false

    @Flag(name: .long, help: "Run IOB and Autosens fixed buggy JavaScript oref algorithms instead of Swift")
    var jsiob_as_fix: Bool = false

    @Flag(name: .long, help: "Run IOB, Autosens, and determine basal fixed buggy JavaScript oref algorithms instead of Swift")
    var jsiob_as_db_fix: Bool = false

    @Option(name: .long, help: "Run IOB, Autosens, and patch of determine basal fixed buggy JavaScript oref algorithms instead of Swift")
    var patch: String?

    public func isRunningJS() -> Bool {
        return js || jsbug || jsiobfix || jsiob_as_fix || jsiob_as_db_fix || patch != nil
    }
}