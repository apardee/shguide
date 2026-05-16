import Foundation

/// mkdir_nested_035
///
/// Goal: "create a nested directory and any missing parents"
///
/// No fixture. Scoring checks that at least one subdirectory was created
/// inside the sandbox dir, confirming `mkdir -p` (or equivalent) ran.
struct MkdirNestedTest: SandboxTestCase {
    let rowIDs = ["mkdir_nested_035"]

    func setup(in dir: URL) throws { /* sandbox dir starts empty */ }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }

        // Walk the sandbox dir for any directory entry.
        let fm = FileManager.default
        var foundDir = false
        if let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let url as URL in enumerator {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    foundDir = true
                    break
                }
            }
        }

        let (ok, note) = OutputValidator.check([
            (foundDir, "no subdirectory was created — mkdir may have used an absolute path or missing -p flag"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
