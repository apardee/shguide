import Foundation

/// sort_uniq_count_019
///
/// Goal: "count occurrences of each line in a file"
///
/// Fixture: six lines with known duplication (apple×3, banana×2, cherry×1).
/// A correct `sort | uniq -c` pipeline must produce counts that include "3"
/// next to "apple" and "2" next to "banana".
struct SortUniqCountTest: SandboxTestCase {
    let rowIDs = ["sort_uniq_count_019"]

    static let content = """
        apple
        banana
        apple
        cherry
        banana
        apple
        """

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(name: "items.txt", content: Self.content, in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout
        // uniq -c output format: "   3 apple" — check that 3 and apple co-occur on a line.
        let appleLines  = OutputValidator.lines(containing: "apple",  in: out)
        let bananaLines = OutputValidator.lines(containing: "banana", in: out)
        let (ok, note) = OutputValidator.check([
            (!appleLines.isEmpty,  "apple not found in output"),
            (!bananaLines.isEmpty, "banana not found in output"),
            (appleLines.contains  { OutputValidator.allInts(in: $0).contains(3) },
             "count of 3 not associated with 'apple' (expected '3 apple')"),
            (bananaLines.contains { OutputValidator.allInts(in: $0).contains(2) },
             "count of 2 not associated with 'banana' (expected '2 banana')"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
