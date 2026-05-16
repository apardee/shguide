import Foundation

/// sed_replace_018
///
/// Goal: "replace foo with bar in every line of a file in place"
///
/// Fixture: a file where every line contains "foo".
/// Scoring checks both stdout (if the model piped output) and the file
/// itself (if the model used sed -i for in-place editing).
/// BSD sed on macOS requires `sed -i ''`; GNU sed uses `sed -i`.
/// Both forms are accepted — we look for "bar" wherever it ends up.
struct SedReplaceTest: SandboxTestCase {
    let rowIDs = ["sed_replace_018"]

    static let fileName = "config.txt"
    static let content = "foo=1\nfoo=2\nfoo=3\n"

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(name: Self.fileName, content: Self.content, in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }

        // Accept substitution appearing in stdout OR written back to the file.
        let inStdout = result.stdout.contains("bar")
        let fileContent = (try? String(contentsOf: dir.appending(path: Self.fileName), encoding: .utf8)) ?? ""
        let inFile = fileContent.contains("bar")

        let (ok, note) = OutputValidator.check([
            (inStdout || inFile,
             "substitution 'bar' not found in stdout or file — sed may have used wrong pattern or wrong filename"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
