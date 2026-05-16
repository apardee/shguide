import Foundation

/// tr_uppercase_043
///
/// Goal: "convert the text in a file to uppercase"
///
/// Fixture: a file with known lowercase content.
/// A correct command (tr a-z A-Z, tr '[:lower:]' '[:upper:]', awk toupper, etc.)
/// must produce output where the known words appear uppercased.
struct TrUppercaseTest: SandboxTestCase {
    let rowIDs = ["tr_uppercase_043"]

    static let fileName = "input.txt"
    static let content  = "hello world\nfoo bar\n"

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
        let (ok, note) = OutputValidator.check([
            (out.contains("HELLO") || out.contains("WORLD"),
             "uppercase output not found — command may not have read the file or wrong transform applied"),
            (!out.contains("hello"),
             "lowercase 'hello' still present — transform was not applied"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
