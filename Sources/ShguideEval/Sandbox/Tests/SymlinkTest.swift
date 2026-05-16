import Foundation

/// ln_symlink_038
///
/// Goal: "make a symbolic link to a file"
///
/// Canonical: ln -s target.txt link.txt
///
/// Fixture: target.txt exists. After the command, a symlink should appear
/// in the sandbox dir pointing to target.txt (or any target). Scoring
/// checks the filesystem state — a correct command creates a symlink entry.
struct SymlinkTest: SandboxTestCase {
    let rowIDs = ["ln_symlink_038"]

    static let targetName = "target.txt"

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(name: Self.targetName, content: "target content\n", in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }

        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []

        // Look for any entry that is a symlink (excluding the original target).
        let hasSymlink = contents.contains { name in
            guard name != Self.targetName else { return false }
            let path = dir.appending(path: name).path
            return (try? fm.destinationOfSymbolicLink(atPath: path)) != nil
        }

        let (ok, note) = OutputValidator.check([
            (hasSymlink,
             "no symlink found in sandbox dir — command may have used absolute paths, missing -s flag, or wrong argument order"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
