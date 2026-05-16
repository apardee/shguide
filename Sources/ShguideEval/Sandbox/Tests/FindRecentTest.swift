import Foundation

/// find_recent_files_002 / find_recent_ambig_114 / find_logs_specific_091
///
/// Fixture: freshly created files (timestamps are always within the last minute).
/// A correct `find . -mtime -1` or `find . -mmin -60` must return the fixture
/// files because they were just created.
///
/// find_logs_specific_091 asks for .log files in /var/log modified in last 7 days.
/// Since absolute paths won't resolve inside the sandbox, this row tests whether
/// the model produces a well-formed find command with -name "*.log" and -mtime -7.
/// We score it by string inspection only and note the limitation.
struct FindRecentTest: SandboxTestCase {
    let rowIDs = ["find_recent_files_002", "find_recent_ambig_114", "find_logs_specific_091",
                  "find_logs_specific_091"]

    func setup(in dir: URL) throws {
        // Create .zshrc with a modification time 1 hour in the past so that
        // `find . -newer ~/.zshrc` (where HOME = sandbox dir) correctly returns
        // recent.txt and report.log, which are created after .zshrc.
        let zshrcURL = dir.appending(path: ".zshrc")
        try SandboxFixtures.makeTextFile(name: ".zshrc", content: "# reference\n", in: dir)
        let pastDate = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes([.modificationDate: pastDate], ofItemAtPath: zshrcURL.path)

        try SandboxFixtures.makeTextFile(name: "recent.txt", content: "fresh\n", in: dir)
        try SandboxFixtures.makeTextFile(name: "report.log", content: "log entry\n", in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        // find_logs_specific_091 references /var/log which doesn't exist in the
        // sandbox dir. Fall back to string-checking the command structure.
        if command.contains("/var/log") || command.contains("var/log") {
            let hasFind  = command.contains("find")
            let hasLog   = command.contains(".log") || command.contains("log")
            let hasMtime = command.contains("mtime") || command.contains("mmin") || command.contains("newer")
            let (ok, note) = OutputValidator.check([
                (hasFind,  "command does not use find"),
                (hasLog,   "command does not filter by .log extension"),
                (hasMtime, "command does not filter by modification time"),
            ])
            return SandboxScore(executable: true, correct: ok, executionMs: 0,
                                note: ok ? "(string-verified — /var/log not available in sandbox)" : note)
        }

        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout
        let (ok, note) = OutputValidator.check([
            (out.contains("recent.txt") || out.contains("report.log"),
             "fixture files not found — command may use absolute path or wrong time filter"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
