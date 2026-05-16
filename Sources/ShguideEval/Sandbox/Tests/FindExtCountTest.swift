import Foundation

/// find_ext_count_124
///
/// Goal: "count how many files of each type are in the current directory tree"
///
/// Fixture: 3 .swift files, 2 .txt files, 1 .json file.
/// A correct command (find + wc per extension, or a loop, or a pipeline)
/// must produce numeric output that reflects those counts.
/// We check that the output contains at least one number and at least one
/// extension name, which catches the common failure of producing no output.
struct FindExtCountTest: SandboxTestCase {
    let rowIDs = ["find_ext_count_124"]

    func setup(in dir: URL) throws {
        for i in 1...3 { try SandboxFixtures.makeTextFile(name: "file\(i).swift", content: "let x = \(i)\n", in: dir) }
        for i in 1...2 { try SandboxFixtures.makeTextFile(name: "doc\(i).txt",   content: "text\n",       in: dir) }
        try SandboxFixtures.makeTextFile(name: "config.json", content: "{}\n", in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout
        let hasNumber = OutputValidator.firstInt(in: out) != nil
        // Accept with or without leading dot: `sed 's/.*\.//'` strips the dot,
        // while `find -name` output retains it.
        let hasExt = out.contains("swift") || out.contains("txt") || out.contains("json")
        let (ok, note) = OutputValidator.check([
            (hasNumber, "no numeric count in output"),
            (hasExt,    "no file extension name in output — command may not be grouping by type"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
