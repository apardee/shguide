import Foundation

/// wc_words_042 / wc_specific_099 / wc_bytes_080 / count_lines_004
///
/// Goal: "count the number of words in a file"
///
/// Fixture: notes.txt with known word/line counts, plus two .swift files
/// so that count_lines_004 ("count lines in all swift files") produces output.
///
/// Actual counts for notes.txt:
/// - words: 51  (7 pangram lines, 6–9 words each)
/// - lines: 7
struct WordCountTest: SandboxTestCase {
    let rowIDs = ["wc_words_042", "wc_specific_099", "wc_bytes_080", "count_lines_004"]

    // 7 lines, 51 words total.
    static let content = """
        the quick brown fox jumps over the lazy dog
        pack my box with five dozen liquor jugs
        how vexingly quick daft zebras jump
        the five boxing wizards jump quickly
        sphinx of black quartz judge my vow
        two driven jocks help fax my big quiz
        five quacking zephyrs jolt my wax bed
        """

    static let fileName = "notes.txt"

    // wc_specific_099 references /tmp/notes.txt. Rewrite to the sandbox-relative
    // fixture name so the command can actually read the file.
    func prepareCommand(_ command: String) -> String {
        command.replacingOccurrences(of: "/tmp/notes.txt", with: "notes.txt")
    }

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(name: Self.fileName, content: Self.content, in: dir)
        // .swift files for count_lines_004 ("count lines in all swift files").
        // Each file has exactly 5 lines.
        let swiftContent = "import Foundation\n\nstruct Foo {\n    let x = 1\n}\n"
        try SandboxFixtures.makeTextFile(name: "main.swift",  content: swiftContent, in: dir)
        try SandboxFixtures.makeTextFile(name: "utils.swift", content: swiftContent, in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout
        let ints = OutputValidator.allInts(in: out)

        // For wc_bytes_080 the model is asked for byte count, not word count.
        // Accept any reasonable non-zero integer in the output.
        // Recognised patterns: wc -c, ls -l | awk '{print $5}', stat, etc.
        let isByteCount = command.contains("-c") || command.contains("bytes")
                       || (command.contains("ls") && command.contains("awk"))
                       || command.contains("stat")
        if isByteCount {
            let (ok, note) = OutputValidator.check([
                (!ints.isEmpty, "no numeric value in output"),
            ])
            return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
        }

        // count_lines_004 asks for lines in .swift files (2 files × 5 lines = 10 total,
        // or 5 per file). Accept any plausible integer ≥ 5.
        if command.contains(".swift") || command.contains("swift") && command.contains("wc") {
            let (ok, note) = OutputValidator.check([
                (!ints.isEmpty, "no numeric value in output — no .swift files matched or wrong path"),
                (ints.contains { $0 >= 5 }, "expected ≥ 5 lines per .swift file, got \(ints)"),
            ])
            return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
        }

        // For word/line count: accept 51 (words) or 7 (lines).
        let (ok, note) = OutputValidator.check([
            (!ints.isEmpty,                    "no numeric value in output"),
            (ints.contains(51) || ints.contains(7),
             "expected 51 (words) or 7 (lines) in output, got \(ints)"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
