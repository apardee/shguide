import Foundation

/// tar_create_007 / compress_ambig_113 — archive creation
/// tar_extract_008 / untar_specific_100 — archive extraction
///
/// Create fixture: a `src/` directory with two known files.
/// A correct `tar -czf` must produce a .tar.gz or .tgz file in the sandbox dir.
///
/// Extract fixture: a pre-built `archive.tar.gz` containing two known files.
/// A correct `tar -xzf` or `tar -xvf` must leave those files on disk.
struct TarCreateExtractTest: SandboxTestCase {
    let rowIDs = ["tar_create_007", "compress_ambig_113", "tar_extract_008", "untar_specific_100",
                  "tar_specific_096"]

    static let srcDir    = "src"
    static let archName  = "archive.tar.gz"
    static let entryFile = "deploy.txt"

    func setup(in dir: URL) throws {
        // Always create src/ — needed by create tests.
        let src = try SandboxFixtures.makeDirectory(name: Self.srcDir, in: dir)
        try SandboxFixtures.makeTextFile(name: "file1.txt", content: "alpha\n", in: src)
        try SandboxFixtures.makeTextFile(name: "file2.txt", content: "beta\n",  in: src)

        // Always create archive.tar.gz — needed by extract tests.
        try SandboxFixtures.makeTarGz(
            archiveName: Self.archName,
            entries: ["file1.txt": "alpha\n", "file2.txt": "beta\n"],
            in: dir
        )
    }

    // untar_specific_100 targets -C /opt/app, which is outside the sandbox dir.
    // Rewrite any absolute -C destination to "." so extraction lands in the
    // sandbox working directory where the scorer can find the files.
    func prepareCommand(_ command: String) -> String {
        guard let range = command.range(of: #"\s+-C\s+/\S+"#, options: .regularExpression) else {
            return command
        }
        return command.replacingCharacters(in: range, with: " -C .")
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }

        // zip -r is also a valid create operation; unzip is the extract counterpart.
        let isCreate = command.contains("-c") || command.contains("czf") || command.contains("create")
                    || (command.hasPrefix("zip") && !command.contains("unzip"))

        if isCreate {
            // Check that a compressed archive now exists in the sandbox dir.
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            let hasArchive = contents.contains {
                $0.hasSuffix(".tar.gz") || $0.hasSuffix(".tgz") || $0.hasSuffix(".tar") || $0.hasSuffix(".zip")
            }
            let (ok, note) = OutputValidator.check([
                (hasArchive, "no archive (.tar.gz / .zip) found after command — wrong flags or missing source path"),
            ])
            return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
        } else {
            // Extract: file1.txt or file2.txt should now exist outside the original archive.
            let fm = FileManager.default
            let file1 = fm.fileExists(atPath: dir.appending(path: "file1.txt").path)
            let file2 = fm.fileExists(atPath: dir.appending(path: "file2.txt").path)
            let (ok, note) = OutputValidator.check([
                (file1 || file2, "extracted files not found — wrong flags, wrong archive name, or wrong destination"),
            ])
            return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
        }
    }
}
