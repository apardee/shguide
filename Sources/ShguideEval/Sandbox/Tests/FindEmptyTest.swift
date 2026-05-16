import Foundation

/// find_empty_032
///
/// Goal: "find empty files in this directory tree"
///
/// Fixture: two 0-byte files and one non-empty file.
/// A correct command must list the empty files and exclude the non-empty one.
struct FindEmptyTest: SandboxTestCase {
    let rowIDs = ["find_empty_032"]

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(name: "empty1.txt", content: "", in: dir)
        try SandboxFixtures.makeTextFile(name: "empty2.log", content: "", in: dir)
        try SandboxFixtures.makeTextFile(name: "notempty.txt", content: "hello world\n", in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout
        let (ok, note) = OutputValidator.check([
            (out.contains("empty1.txt") || out.contains("empty2.log"),
             "no empty file appeared in output"),
            (!out.contains("notempty.txt"),
             "notempty.txt appeared in output — command is not filtering by emptiness"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
