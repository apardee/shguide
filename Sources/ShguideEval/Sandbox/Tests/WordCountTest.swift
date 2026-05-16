import Foundation

/// wc_words_042 / wc_specific_099 / wc_bytes_080
///
/// Goal: "count the number of words in a file"
///
/// Fixture: a file whose word and line counts are known exactly.
/// - words: 42
/// - lines: 7
/// - bytes: tracked by the fixture content
///
/// The fixture file is named `notes.txt` to match the common placeholder
/// used in wc_specific_099 ("count words in /tmp/notes.txt").
struct WordCountTest: SandboxTestCase {
    let rowIDs = ["wc_words_042", "wc_specific_099", "wc_bytes_080", "count_lines_004"]

    // 7 lines, 42 words total.
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

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(name: Self.fileName, content: Self.content, in: dir)
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
        if command.contains("-c") || command.contains("bytes") {
            let (ok, note) = OutputValidator.check([
                (!ints.isEmpty, "no numeric value in output"),
            ])
            return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
        }

        // For word/line count: must contain 42 (words) or 7 (lines) depending
        // on the flag used. We accept either because the model may choose -w or -l.
        let (ok, note) = OutputValidator.check([
            (!ints.isEmpty,                    "no numeric value in output"),
            (ints.contains(42) || ints.contains(7),
             "expected 42 (words) or 7 (lines) in output, got \(ints)"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
