import Foundation

/// diff_files_044
///
/// Goal: "compare two files line by line"
///
/// Fixture: two files that differ on exactly one line.
/// `diff` exits with code 1 when differences are found — that is correct
/// and expected, so `executable` accepts exit code 1.
/// The output must contain the changed line content.
struct DiffFilesTest: SandboxTestCase {
    let rowIDs = ["diff_files_044"]

    static let fileA = "file_a.txt"
    static let fileB = "file_b.txt"
    static let changedToken = "MODIFIED"

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(
            name: Self.fileA,
            content: "alpha\nbeta\ngamma\n",
            in: dir
        )
        try SandboxFixtures.makeTextFile(
            name: Self.fileB,
            content: "alpha\nbeta \(Self.changedToken)\ngamma\n",
            in: dir
        )
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        // diff exits 0 (identical), 1 (differences found), or 2 (error).
        // A well-formed diff command on two differing files should exit 1.
        let timedOut = result.timedOut
        let launchError = result.exitCode == -1 || result.exitCode == 127
        let diffError  = result.exitCode == 2

        guard !timedOut && !launchError else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: timedOut ? "timed out" : "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        guard !diffError else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "diff exited 2 (error): \(result.stderr.prefix(120))")
        }

        let out = result.stdout
        let (ok, note) = OutputValidator.check([
            (result.exitCode == 1,
             result.exitCode == 0
                 ? "command exited 0 with no differences — wrong tool or wrong filenames"
                 : "unexpected exit code \(result.exitCode)"),
            (out.contains(Self.changedToken),
             "changed token '\(Self.changedToken)' not in output — command may not be diff"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
