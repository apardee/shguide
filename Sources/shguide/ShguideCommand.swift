import ArgumentParser
import Foundation
import ShguideCore

@available(macOS 26.0, *)
@main
struct ShguideCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shguide",
        abstract: "Formulate or explain macOS shell commands using Apple's on-device Foundation Models.",
        version: "0.1.0"
    )

    @Flag(name: .customLong("describe"), help: "Explain the given command instead of formulating one.")
    var describe: Bool = false

    @Flag(name: .customLong("config"), help: "Print resolved environment and model availability, then exit.")
    var showConfig: Bool = false

    @Flag(name: .customLong("history"), help: "Include matches from your shell history.")
    var history: Bool = false

    @Flag(name: .customLong("include-destructive"), help: "Allow commands that delete data or modify system state. Shown in red.")
    var includeDestructive: Bool = false

    @Flag(name: .customLong("no-tools"), help: "Disable verification tool calls (faster, lower quality — for eval).")
    var noTools: Bool = false

    @Flag(name: .customLong("json"), help: "Emit JSON instead of an interactive menu.")
    var json: Bool = false

    @Flag(name: .customLong("no-color"), help: "Disable ANSI colour output.")
    var noColor: Bool = false

    @Flag(name: .customLong("mock"), help: "Use the mock engine. Bypasses Foundation Models; useful for UX iteration and tests.")
    var mock: Bool = false

    @Argument(help: "Goal description (default) or command to explain (with --describe). Quote phrases that contain flag-like tokens.")
    var rest: [String] = []

    mutating func run() async throws {
        if showConfig {
            printConfig()
            return
        }
        let input = rest.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else {
            throw ValidationError("Provide a goal (e.g. `shguide find large files`) or pass --describe '<cmd>'.")
        }

        let useMockEnv = ProcessInfo.processInfo.environment["SHGUIDE_ENGINE"]?.lowercased() == "mock"
        let useMock = mock || useMockEnv

        let isTTY = isatty(fileno(stdout)) != 0
        let ansi = ANSI.detect(noColorFlag: noColor, isTTY: isTTY && !json)

        let keywords = describe ? [] : ContextResolver.keywords(from: input)
        let (context, allHistory) = ContextResolver.resolve(
            includeDestructive: includeDestructive,
            useHistory: history,
            useTools: !noTools,
            goalKeywords: keywords
        )

        if describe {
            let exp = try await runDescribe(command: input, context: context, history: allHistory, useMock: useMock)
            if json {
                print(try MenuRenderer.renderDescribeJSON(exp))
            } else {
                print(MenuRenderer.renderDescribe(explanation: exp, ansi: ansi))
            }
            return
        }

        let suggestions = try await runForward(goal: input, context: context, history: allHistory, useMock: useMock)
        if json {
            print(try MenuRenderer.renderJSON(suggestions: suggestions))
            return
        }
        print(MenuRenderer.renderForward(suggestions: suggestions, ansi: ansi))
        if suggestions.isEmpty { return }
        if !isTTY { return }
        promptForSelection(suggestions: suggestions, ansi: ansi)
    }

    private func runForward(
        goal: String,
        context: InvocationContext,
        history: [String],
        useMock: Bool
    ) async throws -> [AnnotatedSuggestion] {
        if useMock {
            return try await MockEngine().forward(goal: goal, context: context)
        }
        let engine = FoundationModelsEngine(useTools: !noTools, history: history)
        return try await engine.forward(goal: goal, context: context)
    }

    private func runDescribe(
        command: String,
        context: InvocationContext,
        history: [String],
        useMock: Bool
    ) async throws -> ForwardExplanation {
        if useMock {
            return try await MockEngine().describe(command: command, context: context)
        }
        let engine = FoundationModelsEngine(useTools: !noTools, history: history)
        return try await engine.describe(command: command, context: context)
    }

    private func promptForSelection(suggestions: [AnnotatedSuggestion], ansi: ANSI) {
        let prompt = "\n" + ansi.dim("Select [1-\(suggestions.count), q]: ")
        FileHandle.standardOutput.write(Data(prompt.utf8))
        guard let line = readLine() else { return }
        let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty || trimmed == "q" || trimmed == "quit" { return }
        guard let n = Int(trimmed), (1...suggestions.count).contains(n) else {
            print(ansi.dim("(no selection — nothing copied)"))
            return
        }
        let picked = suggestions[n - 1]
        if Pasteboard.copy(picked.command) {
            print(ansi.green("✓ copied:") + " " + picked.command)
        } else {
            print(picked.command)
            print(ansi.dim("(pbcopy unavailable — command printed above)"))
        }
    }
}

@available(macOS 26.0, *)
extension ShguideCommand {
    func printConfig() {
        let env = ProcessInfo.processInfo.environment
        let path = PathInventory.snapshot(env: env)
        print("shell:       \(env["SHELL"] ?? "?")")
        print("os:          \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("PATH binaries detected: \(path.count)")
        if let hist = ShellHistory.defaultPath() {
            let exists = FileManager.default.fileExists(atPath: hist.path)
            print("history:     \(hist.path) \(exists ? "(present)" : "(missing)")")
        } else {
            print("history:     <unknown>")
        }
        do {
            try FoundationModelsEngine.ensureAvailable()
            print("model:       available")
        } catch let err as EngineError {
            print("model:       \(err.description)")
        } catch {
            print("model:       \(error)")
        }
    }
}

// FileHandle.standardOutput on macOS exposes a file descriptor via .fileDescriptor; isatty wants a CInt.
private var stdout: UnsafeMutablePointer<FILE> { Darwin.stdout }
