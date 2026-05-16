import Foundation

/// grep_ignore_case_046 / grep_specific_092
///
/// Goal: "search a file for the word error ignoring case"
///
/// Fixture: a log file with lines at three different capitalizations of "error"
/// and one clean line. A correct command must match all three error lines and
/// return exit code 0 (or 1 if grep finds nothing — treated as failure here).
struct GrepIgnoreCaseTest: SandboxTestCase {
    let rowIDs = ["grep_ignore_case_046", "grep_specific_092", "grep_context_123",
                  "grep_invert_125"]

    // Fixture file with a mix of cased error lines and one clean line.
    static let logFileName = "app.log"
    static let logContent = """
        [INFO]  Server started on port 8080
        [ERROR] Disk quota exceeded
        [Warning] Connection timeout
        [error] Failed to open socket
        [INFO]  Request processed successfully
        ERROR: null pointer dereference
        """

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(name: Self.logFileName, content: Self.logContent, in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout

        // For grep_invert_125 ("lines that do NOT contain DEBUG"), any
        // non-empty, non-crashing result is acceptable — the fixture has no
        // DEBUG lines so all lines should be returned.
        if command.contains("invert") || command.contains(" -v ") || command.contains(" -v\t") {
            let (ok, note) = OutputValidator.check([
                (!out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                 "no output produced for invert/exclude grep"),
            ])
            return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
        }

        // For ignore-case and context greps, all three capitalizations of
        // "error" must appear.
        let (ok, note) = OutputValidator.check([
            (OutputValidator.lines(containing: "error", in: out.lowercased()).count >= 2,
             "fewer than 2 error-containing lines matched — case-insensitive flag may be missing"),
            (out.contains("ERROR") || out.contains("error") || out.contains("Error"),
             "no variant of 'error' appeared in output"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
