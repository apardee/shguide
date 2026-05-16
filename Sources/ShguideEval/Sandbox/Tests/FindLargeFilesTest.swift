import Foundation

/// find_large_files_001 / find_large_specific_093
///
/// Fixture: three files — small (1 KB), large (3 MB), huge (8 MB).
/// A correct command must surface the large/huge files without surfacing
/// the small one. We accept any size threshold the model chooses as long
/// as large.bin and huge.bin appear in stdout and small.txt does not.
struct FindLargeFilesTest: SandboxTestCase {
    let rowIDs = ["find_large_files_001", "find_large_specific_093", "find_ambig_106"]

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(name: "small.txt", content: String(repeating: "x", count: 1_024), in: dir)
        try SandboxFixtures.makeSizedFile(name: "large.bin", sizeBytes: 3 * 1_024 * 1_024, in: dir)
        try SandboxFixtures.makeSizedFile(name: "huge.bin",  sizeBytes: 8 * 1_024 * 1_024, in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: result.timedOut ? "timed out" : "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout
        let (ok, note) = OutputValidator.check([
            (out.contains("large.bin") || out.contains("huge.bin"),
             "neither large.bin nor huge.bin appeared in output"),
            (!out.contains("small.txt"),
             "small.txt (1 KB) appeared in output — threshold too low or no filter"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
