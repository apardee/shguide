import Foundation

/// grep_context_123
///
/// Goal: "search a log file for ERROR and show 3 lines of context around each match"
///
/// The canonical form is a single compound-flag command:
///   grep -C 3 "ERROR" app.log       (symmetric context)
///   grep -A 3 -B 3 "ERROR" app.log  (explicit before/after)
///
/// Fixture: a log file where ERROR appears at line 5, surrounded by
/// identifiable context lines before and after.
/// A correct command must return the ERROR line AND lines from the
/// surrounding context — not just the ERROR line alone.
struct GrepContextTest: SandboxTestCase {
    let rowIDs = ["grep_context_123"]

    static let fileName = "app.log"
    static let content = """
        [INFO]  startup complete
        [INFO]  loading config
        [DEBUG] config key=value
        [INFO]  connecting to database
        [ERROR] connection refused: timeout after 30s
        [INFO]  retrying in 5 seconds
        [DEBUG] attempt 2 of 3
        [INFO]  retry succeeded
        """

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(name: Self.fileName, content: Self.content, in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout
        // Must contain the ERROR line itself.
        let hasError = out.contains("ERROR") || out.contains("connection refused")
        // Must contain at least one surrounding context line.
        let hasContext = out.contains("connecting to database")    // line before
                      || out.contains("retrying in 5 seconds")     // line after
                      || out.contains("loading config")             // two before
                      || out.contains("attempt 2 of 3")             // two after
        let (ok, note) = OutputValidator.check([
            (hasError,   "ERROR line not in output — wrong pattern or wrong filename"),
            (hasContext, "no context lines around ERROR — missing -C/-A/-B flag"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
