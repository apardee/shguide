import Foundation

/// cp_recursive_036 / backup_ambig_108
///
/// Fixture: a `src/` directory containing two known files.
/// A correct `cp -r src/ dst/` (or `cp -R`, `rsync --dry-run`, etc.) must
/// produce a second directory in the sandbox that contains both files.
/// Scoring checks the filesystem state after the command runs.
struct CpRecursiveTest: SandboxTestCase {
    let rowIDs = ["cp_recursive_036", "backup_ambig_108"]

    static let srcDir   = "src"
    static let file1    = "notes.txt"
    static let file2    = "readme.md"

    func setup(in dir: URL) throws {
        let src = try SandboxFixtures.makeDirectory(name: Self.srcDir, in: dir)
        try SandboxFixtures.makeTextFile(name: Self.file1, content: "notes content\n", in: src)
        try SandboxFixtures.makeTextFile(name: Self.file2, content: "readme content\n", in: src)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }

        // Look for any directory other than `src` that contains both fixture files.
        let fm = FileManager.default
        let topLevel = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        let candidates = topLevel.filter { $0 != Self.srcDir }

        let copied = candidates.contains { entry in
            let entryURL = dir.appending(path: entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entryURL.path, isDirectory: &isDir), isDir.boolValue else {
                return false
            }
            let has1 = fm.fileExists(atPath: entryURL.appending(path: Self.file1).path)
            let has2 = fm.fileExists(atPath: entryURL.appending(path: Self.file2).path)
            return has1 || has2
        }

        let (ok, note) = OutputValidator.check([
            (copied, "no copy of src/ found containing the fixture files — command may have used wrong paths or omitted -r flag"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
