import Foundation

/// disk_usage_005 / diskspace_ambig_109
///
/// Goal: "show disk usage of each subdirectory in the current folder, human readable"
///
/// The canonical command is a two-stage pipeline:
///   du -sh */ | sort -h
///
/// Fixture: three subdirectories. A correct command must produce one output
/// line per subdirectory containing a human-readable size unit (K/M/G/B)
/// and the directory name. We also check the output has multiple lines,
/// confirming the model didn't just run `du` on the whole tree.
struct DiskUsageSortTest: SandboxTestCase {
    let rowIDs = ["disk_usage_005", "diskspace_ambig_109"]

    func setup(in dir: URL) throws {
        for name in ["alpha", "beta", "gamma"] {
            let sub = try SandboxFixtures.makeDirectory(name: name, in: dir)
            try SandboxFixtures.makeTextFile(name: "file.txt", content: "data\n", in: sub)
        }
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout
        let lines = out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        // Each du output line ends with a path; size units appear as K/M/G suffix.
        let hasUnits = lines.contains { $0.contains("K") || $0.contains("M") || $0.contains("G") || $0.contains("B") }
        let hasDir   = lines.contains { $0.contains("alpha") || $0.contains("beta") || $0.contains("gamma") }
        let (ok, note) = OutputValidator.check([
            (lines.count >= 2,  "fewer than 2 output lines — command may have used wrong path or missing wildcard"),
            (hasUnits,          "no human-readable size unit (K/M/G) in output — missing -h flag"),
            (hasDir,            "fixture directory names not in output — du may be reading wrong path"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
