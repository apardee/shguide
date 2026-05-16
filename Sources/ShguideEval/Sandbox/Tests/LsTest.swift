import Foundation

/// ls_hidden_033 / ls_long_034 / file_count_025
///
/// Fixture: two visible files and one hidden file (.hidden).
/// ls_hidden_033: `ls -a` or `ls -la` must show `.hidden`.
/// ls_long_034:   `ls -l` must show permission bits (lines starting with -rw or drw).
/// file_count_025: `ls | wc -l` or `find . -type f | wc -l` must produce a count ≥ 2.
struct LsTest: SandboxTestCase {
    let rowIDs = ["ls_hidden_033", "ls_long_034", "file_count_025"]

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(name: "visible1.txt", content: "a\n", in: dir)
        try SandboxFixtures.makeTextFile(name: "visible2.txt", content: "b\n", in: dir)
        try SandboxFixtures.makeTextFile(name: ".hidden",      content: "h\n", in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout

        // file_count_025: output should be a number ≥ 2.
        if command.contains("wc") || command.contains("count") {
            let n = OutputValidator.firstInt(in: out) ?? 0
            let (ok, note) = OutputValidator.check([
                (n >= 2, "count in output was \(n), expected ≥ 2"),
            ])
            return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
        }

        // ls_hidden_033: .hidden must appear.
        if command.contains("-a") || command.contains("-A") || command.contains("hidden") {
            let (ok, note) = OutputValidator.check([
                (out.contains(".hidden"), ".hidden file not listed — missing -a flag or wrong directory"),
            ])
            return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
        }

        // ls_long_034: output should contain permission-style lines (rw or drw prefix).
        let hasPerms = out.contains("-rw") || out.contains("drw") || out.contains("-r-") || out.contains("total")
        let (ok, note) = OutputValidator.check([
            (!out.isEmpty, "no output — wrong directory or command failed silently"),
            (hasPerms,     "output does not look like long listing — missing -l flag"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
