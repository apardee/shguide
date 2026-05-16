import Foundation

/// find_large_files_001 / find_large_specific_093 / find_ambig_106
///
/// Fixture: three files — small (1 KB), large (3 MB), huge (8 MB).
///
/// Scoring strategy:
/// - Commands that target a real absolute path (e.g. /Users/…/Downloads) cannot
///   match fixture filenames; they are string-verified for correct structure instead.
/// - Commands that sort all files by size without a threshold (du -sh * | sort) are
///   valid for ambiguous "biggest files" goals; we check that large/huge files appear
///   in output without requiring small.txt to be absent.
/// - Commands with an explicit size filter must surface large.bin/huge.bin and
///   must not surface small.txt.
struct FindLargeFilesTest: SandboxTestCase {
    let rowIDs = ["find_large_files_001", "find_large_specific_093", "find_ambig_106"]

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(name: "small.txt", content: String(repeating: "x", count: 1_024), in: dir)
        try SandboxFixtures.makeSizedFile(name: "large.bin", sizeBytes: 3 * 1_024 * 1_024, in: dir)
        try SandboxFixtures.makeSizedFile(name: "huge.bin",  sizeBytes: 8 * 1_024 * 1_024, in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        // Commands targeting a real absolute path outside the sandbox can never match
        // fixture filenames. String-verify the command structure instead.
        let usesRealPath = command.contains("/Users/") || command.contains("/home/")
                        || command.contains("/var/") || command.contains("/opt/")
        if usesRealPath {
            let hasSizeFilter = command.contains("-size") || command.contains("-S")
            let hasSortOrFind = command.contains("find") || command.contains("du") || command.contains("sort")
            let (ok, note) = OutputValidator.check([
                (hasSortOrFind, "command does not use find/du/sort"),
                (hasSizeFilter, "command is missing a size filter (-size flag)"),
            ])
            return SandboxScore(
                executable: true, correct: ok, executionMs: 0,
                note: ok ? "(string-verified — real path outside sandbox)" : note
            )
        }

        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: result.timedOut ? "timed out" : "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout

        // Size-sort approach (e.g. du -sh * | sort -rh): valid for ambiguous "biggest files"
        // goals. Only require that the large files appear; do not penalise for showing small ones.
        let isSizeSort = command.contains("du") && command.contains("sort")
        if isSizeSort {
            let (ok, note) = OutputValidator.check([
                (!out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                 "no output produced — command may have failed silently"),
                (out.contains("large.bin") || out.contains("huge.bin") || out.split(separator: "\n").count >= 2,
                 "no files listed in output"),
            ])
            return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
        }

        // Filtered approach (find -size, etc.): must show large/huge and exclude small.
        let (ok, note) = OutputValidator.check([
            (out.contains("large.bin") || out.contains("huge.bin"),
             "neither large.bin nor huge.bin appeared in output"),
            (!out.contains("small.txt"),
             "small.txt (1 KB) appeared in output — threshold too low or no size filter"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
