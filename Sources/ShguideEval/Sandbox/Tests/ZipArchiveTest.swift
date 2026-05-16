import Foundation

/// zip_create_066 / unzip_file_067
///
/// zip_create_066: "create a zip archive of a directory and its contents"
///   Canonical: zip -r archive.zip src/
///   Fixture: a src/ directory with two files.
///   Scoring checks a .zip file was created in the sandbox dir.
///
/// unzip_file_067: "extract a zip archive into the current directory"
///   Canonical: unzip archive.zip
///   Fixture: a pre-built archive.zip containing two known files.
///   Scoring checks the extracted files appear in the sandbox dir.
struct ZipArchiveTest: SandboxTestCase {
    let rowIDs = ["zip_create_066", "unzip_file_067"]

    static let zipName  = "archive.zip"
    static let srcDir   = "src"
    static let file1    = "alpha.txt"
    static let file2    = "beta.txt"

    func setup(in dir: URL) throws {
        // src/ for the create test
        let src = try SandboxFixtures.makeDirectory(name: Self.srcDir, in: dir)
        try SandboxFixtures.makeTextFile(name: Self.file1, content: "alpha\n", in: src)
        try SandboxFixtures.makeTextFile(name: Self.file2, content: "beta\n",  in: src)

        // Pre-built archive.zip for the extract test
        let zipPath = dir.appending(path: Self.zipName).path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", zipPath, Self.srcDir]
        process.currentDirectoryURL = dir
        try process.run()
        process.waitUntilExit()
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }

        let fm  = FileManager.default
        let isCreate = command.contains("-r") || command.contains("zip") && !command.contains("unzip")
        let isExtract = command.hasPrefix("unzip") || command.contains("unzip ")

        if isExtract {
            // Extracted files should appear directly in the sandbox or in src/
            let direct1 = fm.fileExists(atPath: dir.appending(path: Self.file1).path)
            let direct2 = fm.fileExists(atPath: dir.appending(path: Self.file2).path)
            let nested1 = fm.fileExists(atPath: dir.appending(path: "\(Self.srcDir)/\(Self.file1)").path)
            let (ok, note) = OutputValidator.check([
                (direct1 || direct2 || nested1,
                 "extracted files not found in sandbox dir — wrong archive name or wrong destination"),
            ])
            return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
        }

        // Create: a .zip file must now exist
        let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        let hasZip   = contents.contains { $0.hasSuffix(".zip") }
        let (ok, note) = OutputValidator.check([
            (hasZip, "no .zip archive found after command — wrong flags or missing -r for directory"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
