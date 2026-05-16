import Foundation

/// Shared output-checking helpers for `SandboxTestCase.score` implementations.
enum OutputValidator {

    // MARK: - Executability

    /// True when the command ran without a launcher error, timeout, or
    /// "command not found" response. Exit code 1 is allowed (diff, grep).
    static func executable(_ result: ExecutionResult) -> Bool {
        result.launched
    }

    // MARK: - String presence

    static func allPresent(_ needles: [String], in text: String) -> Bool {
        needles.allSatisfy { text.contains($0) }
    }

    static func anyPresent(_ needles: [String], in text: String) -> Bool {
        needles.contains { text.contains($0) }
    }

    static func nonePresent(_ needles: [String], in text: String) -> Bool {
        needles.allSatisfy { !text.contains($0) }
    }

    // MARK: - Line operations

    static func lineCount(_ text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    static func lines(containing needle: String, in text: String) -> [String] {
        text.split(separator: "\n").map(String.init).filter { $0.contains(needle) }
    }

    /// Returns the first integer that appears anywhere in `text`, or nil.
    static func firstInt(in text: String) -> Int? {
        for match in text.matches(of: #/\b(\d+)\b/#) {
            if let v = Int(match.output.1) { return v }
        }
        return nil
    }

    /// Returns ALL integers found in `text` (left-to-right).
    static func allInts(in text: String) -> [Int] {
        text.matches(of: #/\b(\d+)\b/#).compactMap { Int($0.output.1) }
    }

    // MARK: - Combined pass/note helper

    /// Returns `(pass, note)` where `note` is empty on pass and describes the
    /// first failing condition on failure. Avoids repeating the condition/note
    /// pair pattern across every test case.
    static func check(_ conditions: [(Bool, String)]) -> (Bool, String) {
        for (ok, note) in conditions {
            if !ok { return (false, note) }
        }
        return (true, "")
    }
}
