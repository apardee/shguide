import ArgumentParser

@available(macOS 26.0, *)
@main
struct EvalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shguide-eval",
        abstract: "Evaluation harness for the shguide query engine.",
        subcommands: [RunCommand.self, CompareCommand.self]
    )
}
