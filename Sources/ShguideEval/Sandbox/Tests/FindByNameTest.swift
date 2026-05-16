import Foundation

/// find_by_name_031
///
/// Goal: "find all files named config.json under the current directory"
///
/// Fixture: two config.json files in different subdirectories plus a
/// decoy with a different name, to confirm the command is filtering by
/// name and not just listing everything.
struct FindByNameTest: SandboxTestCase {
    let rowIDs = ["find_by_name_031"]

    func setup(in dir: URL) throws {
        let src = try SandboxFixtures.makeDirectory(name: "src", in: dir)
        let lib = try SandboxFixtures.makeDirectory(name: "src/lib", in: dir)
        _ = lib  // silence unused warning; directory is created as side effect above
        try SandboxFixtures.makeTextFile(name: "config.json", content: #"{"env":"prod"}"#, in: src)
        let srcLib = src.appending(path: "lib")
        try SandboxFixtures.makeTextFile(name: "config.json", content: #"{"env":"dev"}"#, in: srcLib)
        try SandboxFixtures.makeTextFile(name: "README.md", content: "# project", in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout
        let (ok, note) = OutputValidator.check([
            (out.contains("config.json"),    "config.json not found in output"),
            (!out.contains("README.md"),     "README.md (decoy) appeared in output"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
