import Foundation

/// tar_list_068 / tar_specific_096
///
/// Goal: "list the contents of a tar.gz archive without extracting"
///
/// Fixture: a real .tar.gz archive containing three known entries.
/// A correct `tar -tf archive.tar.gz` must print all three paths.
/// The sandbox also confirms that no extraction side-effects occur (the
/// staging directory should not reappear after setup cleanup).
struct TarListTest: SandboxTestCase {
    let rowIDs = ["tar_list_068"]

    static let archiveName = "archive.tar.gz"
    static let entries: [String: String] = [
        "file1.txt":         "hello from file one\n",
        "file2.txt":         "hello from file two\n",
        "subdir/file3.txt":  "hello from nested file\n",
    ]

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTarGz(
            archiveName: Self.archiveName,
            entries: Self.entries,
            in: dir
        )
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout
        let (ok, note) = OutputValidator.check([
            (out.contains("file1.txt"),        "file1.txt not listed in archive output"),
            (out.contains("file2.txt"),        "file2.txt not listed in archive output"),
            (out.contains("subdir/file3.txt"), "subdir/file3.txt not listed in archive output"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
