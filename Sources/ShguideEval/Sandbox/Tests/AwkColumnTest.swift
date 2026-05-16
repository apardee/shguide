import Foundation

/// awk_column_017 / awk_nth_col_122
///
/// Goal: "print the second column of a space-delimited file" (or third for _122)
///
/// Fixture: a four-row space-delimited file with known column values.
/// - Col 1: one, four, seven, ten
/// - Col 2: two, five, eight, eleven
/// - Col 3: three, six, nine, twelve
///
/// A correct `awk '{print $2}'` must output the col-2 values and must NOT
/// output col-1 or col-3 values.
struct AwkColumnTest: SandboxTestCase {
    let rowIDs = ["awk_column_017", "awk_nth_col_122"]

    static let content = """
        one two three
        four five six
        seven eight nine
        ten eleven twelve
        """

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(name: "data.txt", content: Self.content, in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout

        // awk_nth_col_122 asks for column 3 (tab-delimited in its prompt,
        // space-delimited in the fixture — both produce the same result here).
        let wantsCol3 = command.contains("$3") || command.contains("awk_nth")
            || command.contains("third") || command.contains("3rd")

        if wantsCol3 {
            let (ok, note) = OutputValidator.check([
                (OutputValidator.allPresent(["three", "six", "nine", "twelve"], in: out),
                 "col-3 values (three/six/nine/twelve) not all present in output"),
                (OutputValidator.nonePresent(["one", "four", "seven", "ten"], in: out),
                 "col-1 values appeared in output — wrong column extracted"),
            ])
            return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
        }

        let (ok, note) = OutputValidator.check([
            (OutputValidator.allPresent(["two", "five", "eight", "eleven"], in: out),
             "col-2 values (two/five/eight/eleven) not all present in output"),
            (OutputValidator.nonePresent(["one", "four", "seven", "ten"], in: out),
             "col-1 values appeared in output — wrong column extracted"),
            (OutputValidator.nonePresent(["three", "six", "nine", "twelve"], in: out),
             "col-3 values appeared in output — too many columns printed"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
