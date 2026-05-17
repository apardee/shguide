import ArgumentParser
import Foundation
import ShguideCore

@available(macOS 26.0, *)
@main
struct ShguideCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shguide",
        abstract:
            "Formulate or explain macOS shell commands using Apple's on-device Foundation Models.",
        version: "0.1.0"
    )

    @Flag(
        name: .customLong("describe"), help: "Explain the given command instead of formulating one."
    )
    var describe: Bool = false

    @Flag(
        name: .customLong("config"),
        help: "Print resolved environment and model availability, then exit.")
    var showConfig: Bool = false

    @Flag(name: .customLong("history"), help: "Include matches from your shell history.")
    var history: Bool = false

    @Flag(
        name: .customLong("include-destructive"),
        help: "Allow commands that delete data or modify system state. Shown in red.")
    var includeDestructive: Bool = false

    @Flag(
        name: .customLong("tools"),
        help:
            "Enable manPage/checkCommand tool calls. Off by default — current eval shows no quality benefit and a 30-60× slowdown."
    )
    var tools: Bool = false

    @Flag(name: .customLong("json"), help: "Emit JSON instead of an interactive menu.")
    var json: Bool = false

    @Flag(name: .customLong("no-color"), help: "Disable ANSI colour output.")
    var noColor: Bool = false

    @Flag(
        name: .customLong("mock"),
        help: "Use the mock engine. Bypasses Foundation Models; useful for UX iteration and tests.")
    var mock: Bool = false

    @Option(
        name: .customLong("shell-init"),
        help:
            "Print shell integration for the given shell (zsh, bash, fish), then exit. Usage: eval \"$(shguide --shell-init zsh)\""
    )
    var shellInit: String?

    @Argument(
        help:
            "Goal description (default) or command to explain (with --describe). Quote phrases that contain flag-like tokens."
    )
    var rest: [String] = []

    mutating func run() async throws {
        if let shell = shellInit {
            printShellInit(for: shell)
            return
        }

        if showConfig {
            printConfig()
            return
        }

        let input = rest.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else {
            throw ValidationError(
                "Provide a goal (e.g. `shguide find large files`) or pass --describe '<cmd>'.")
        }

        let useMockEnv =
            ProcessInfo.processInfo.environment["SHGUIDE_ENGINE"]?.lowercased() == "mock"
        let useMock = mock || useMockEnv

        // stdout being a TTY means direct invocation; not a TTY means inside $(...) or a pipe.
        // stderr being a TTY tells us a terminal is reachable at all (it's visible in both cases).
        let stdoutIsTTY = isatty(STDOUT_FILENO) != 0
        let stderrIsTTY = isatty(STDERR_FILENO) != 0
        let hasTerminal = stdoutIsTTY || stderrIsTTY

        // ANSI: enable when a terminal is visible (covers direct invocation and $(...)).
        let ansi = ANSI.detect(noColorFlag: noColor, isTTY: hasTerminal && !json)

        let keywords = describe ? [] : ContextResolver.keywords(from: input)
        let (context, allHistory) = ContextResolver.resolve(
            includeDestructive: includeDestructive,
            useHistory: history,
            useTools: tools,
            goalKeywords: keywords
        )

        if describe {
            let exp = try await runDescribe(
                command: input, context: context, history: allHistory, useMock: useMock)
            if json {
                print(try MenuRenderer.renderDescribeJSON(exp))
            } else {
                print(MenuRenderer.renderDescribe(explanation: exp, ansi: ansi))
            }
            return
        }

        // Spinner writes to stderr — visible in both direct and $(...) invocations.
        let suggestions = try await withSpinner(label: "Working…", enabled: stderrIsTTY && !json) {
            try await runForward(
                goal: input, context: context, history: allHistory, useMock: useMock)
        }

        if json {
            print(try MenuRenderer.renderJSON(suggestions: suggestions))
            return
        }

        if suggestions.isEmpty {
            let msg = ansi.dim(
                "No suggestions. Try rephrasing the goal, or pass --include-destructive if the answer requires a risky command.\n"
            )
            fputs(msg, Darwin.stderr)
            return
        }

        // No terminal reachable at all (CI, script redirect) — emit plain text to stdout.
        if !hasTerminal {
            print(MenuRenderer.renderForward(suggestions: suggestions, ansi: ansi))
            return
        }

        // Carousel opens /dev/tty internally, so it works in both direct and $(...) invocations.
        let picked = await Task.detached {
            Carousel.run(suggestions: suggestions, ansi: ansi)
        }.value

        guard let picked else { return }

        // stdout is captured by the shell wrapper in $(...); the wrapper injects it into
        // the readline buffer. Clipboard is a fallback for sessions without the wrapper.
        print(picked.command)
        Pasteboard.copy(picked.command)
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
        let engine = FoundationModelsEngine(useTools: tools, history: history)
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
        let engine = FoundationModelsEngine(useTools: tools, history: history)
        return try await engine.describe(command: command, context: context)
    }
}

// MARK: - Shell init

@available(macOS 26.0, *)
extension ShguideCommand {
    private func printShellInit(for shell: String) {
        switch shell.lowercased() {
        case "zsh": print(zshInit)
        case "bash": print(bashInit)
        case "fish": print(fishInit)
        default:
            fputs("shguide: unknown shell '\(shell)'. Supported: zsh, bash, fish\n", Darwin.stderr)
        }
    }

    // Resolve the binary's own path so the wrapper works regardless of whether
    // shguide is on PATH (e.g. during development with .build/debug/shguide).
    private var resolvedBinaryPath: String {
        let arg0 = CommandLine.arguments[0]
        if let resolved = realpath(arg0, nil) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        if arg0.hasPrefix("/") { return arg0 }
        return FileManager.default.currentDirectoryPath + "/" + arg0
    }

    // zsh: print -z injects the command into the ZLE readline buffer.
    // The prompt shows the command ready to edit/run; history records it on execution.
    private var zshInit: String {
        let bin = resolvedBinaryPath
        return """
            shguide() {
              local cmd
              cmd=$('\(bin)' "$@") || return
              [[ -n $cmd ]] && print -z -- "$cmd"
            }
            """
    }

    // bash: no readline-inject API exists for regular functions (READLINE_LINE only works
    // inside bind -x callbacks). Best available: add to history for ↑ recall.
    private var bashInit: String {
        let bin = resolvedBinaryPath
        return """
            shguide() {
              local cmd
              cmd=$('\(bin)' "$@") || return
              [[ -n $cmd ]] || return
              history -s -- "$cmd"
              printf '  (added to history — press ↑ to recall)\\n' >&2
            }
            """
    }

    // fish: commandline sets the interactive input buffer directly.
    private var fishInit: String {
        let bin = resolvedBinaryPath
        return """
            function shguide
                set cmd ('\(bin)' $argv)
                or return
                test -n "$cmd"; and commandline -- $cmd
            end
            """
    }
}

// MARK: - Config

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
