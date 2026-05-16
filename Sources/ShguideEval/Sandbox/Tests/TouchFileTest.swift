import Foundation

/// touch_create_037
///
/// Goal: "create an empty file called placeholder"
///
/// No fixture needed. Scoring checks the filesystem state after the command
/// runs — looks for any newly created regular file in the sandbox dir.
/// The model's exact filename choice doesn't matter; what matters is that
/// a file was created.
struct TouchFileTest: SandboxTestCase {
    let rowIDs = ["touch_create_037"]

    func setup(in dir: URL) throws { /* sandbox dir starts empty */ }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }

        // Check that at least one regular file now exists in the sandbox dir.
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let hasFile = contents.contains { name in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: dir.appending(path: name).path, isDirectory: &isDir)
            return !isDir.boolValue
        }

        let (ok, note) = OutputValidator.check([
            (hasFile, "no file was created in the sandbox directory — touch may have used an absolute path or failed silently"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
