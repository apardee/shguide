import Foundation

/// Structural decomposition of a shell command used by the binary-set scorer.
/// Splits a command on shell operators and returns the first "real" binary of each stage,
/// applying an alias map so `fd`/`find`, `rg`/`grep`, `bat`/`cat` count as equivalent.
enum CommandShape {
    /// Common modern-alternative → canonical binary map. Single-direction by design:
    /// nl2bash canonicals tend to use the canonical (`find`/`grep`), and we want to
    /// accept suggestions that use the alternative.
    static let aliases: [String: String] = [
        "fd": "find",
        "rg": "grep",
        "bat": "cat",
    ]

    static func binaries(in command: String) -> [String] {
        splitStages(command).compactMap { firstBinary(stage: $0) }
    }

    static func binarySet(in command: String) -> Set<String> {
        Set(binaries(in: command))
    }

    /// Pass criterion: first binary matches AND canonical's binary set is a subset
    /// of the suggestion's. Strict-subset is intentionally tight; we report FN rate
    /// from spot-checks alongside the metric.
    static func suggestionCoversCanonical(suggestion: String, canonical: String) -> Bool {
        let sBins = binaries(in: suggestion)
        let cBins = binaries(in: canonical)
        guard let sFirst = sBins.first, let cFirst = cBins.first else { return false }
        if sFirst != cFirst { return false }
        return Set(cBins).isSubset(of: Set(sBins))
    }

    private static func splitStages(_ command: String) -> [String] {
        // Naive split — no quote awareness. Good enough for the corpus we sample:
        // we filter out rows that embed scripts, so | / && / || / ; are operators.
        command
            .split(separator: #/\s*(?:\|\||&&|;|\|)\s*/#)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func firstBinary(stage: String) -> String? {
        var s = stage
        while s.hasPrefix("(") || s.hasPrefix("`") || s.hasPrefix("$") {
            s.removeFirst()
            if s.hasPrefix("(") { s.removeFirst() } // for "$("
        }
        s = s.trimmingCharacters(in: .whitespaces)
        let tokens = s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        for tok in tokens {
            // Skip leading env-var assignments like FOO=bar.
            if isEnvAssignment(tok) { continue }
            // Skip sudo / time / nohup wrappers — we care about the real binary.
            if tok == "sudo" || tok == "time" || tok == "nohup" { continue }
            // Strip leading punctuation introduced by command substitution that survived.
            let cleaned = tok.trimmingCharacters(in: CharacterSet(charactersIn: "()`\"'"))
            guard !cleaned.isEmpty else { continue }
            let lower = cleaned.lowercased()
            return aliases[lower] ?? lower
        }
        return nil
    }

    private static func isEnvAssignment(_ token: String) -> Bool {
        guard let eq = token.firstIndex(of: "=") else { return false }
        let lhs = token[..<eq]
        guard let first = lhs.first, first.isLetter || first == "_" else { return false }
        return lhs.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
