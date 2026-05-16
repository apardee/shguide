import Foundation

/// head_first_039 / tail_last_040 / view_file_ambig_112
///
/// Fixture: a file with 60 numbered lines.
/// head: first 20 lines — "line 1" must appear, "line 60" must not.
/// tail: last 50 lines — "line 60" must appear, "line 1" must not
///       (only lines 11–60 survive tail -n 50 on a 60-line file).
struct HeadTailTest: SandboxTestCase {
    let rowIDs = ["head_first_039", "tail_last_040", "view_file_ambig_112"]

    static let fileName = "logfile.txt"
    static let content: String = (1...60).map { "line \($0)" }.joined(separator: "\n") + "\n"

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
        let isTail = command.contains("tail")

        let (ok, note): (Bool, String)
        if isTail {
            (ok, note) = OutputValidator.check([
                (out.contains("line 60"), "line 60 not in tail output"),
                (!out.contains("line 1\n") && !out.contains("line 1 "),
                 "line 1 appeared in tail output — too many lines returned or wrong tool"),
            ])
        } else {
            (ok, note) = OutputValidator.check([
                (out.contains("line 1"),  "line 1 not in head output"),
                (!out.contains("line 60"), "line 60 appeared in head output — too many lines returned"),
            ])
        }
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
