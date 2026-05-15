import Foundation
import ShguideCore

// MARK: - Legacy types (used by old RunCommand path, kept for AggregateReport compat)

struct Trial: Encodable {
    let coverage: Bool
    let validity: Bool
    let safety: Bool
    let latencySeconds: Double
    let suggestionsReturned: Int
    let firstSuggestion: String?
    let allSuggestions: [String]?
    let explanationSummary: String?
    let error: String?
}

struct RowResult: Encodable {
    let id: String
    let mode: String
    let trials: [Trial]
    let coverageRate: Double
    let validityRate: Double
    let safetyRate: Double
    let stable: Bool
    let medianLatencySeconds: Double
}

struct AggregateReport: Encodable {
    let dataset: String
    let strategy: String
    let promptVariant: String
    let temperature: Double
    let seeds: Int
    let totalRows: Int
    let forwardCoverageRate: Double
    let forwardCoverageStrictRate: Double
    let forwardValidityRate: Double
    let safetyRate: Double
    let stabilityRate: Double
    let medianLatencySeconds: Double
    let p95LatencySeconds: Double
    let rows: [RowResult]
}

// MARK: - Scored output types (phase-2 scoring)

struct ScoredTrial: Encodable {
    let seed: Int
    let coverage: Bool
    let validity: Bool
    let safety: Bool
    let specificity: Double     // 0–1: fraction of goal-specific values present in best suggestion
    let accuracy: Double?       // nil when no canonical; Jaccard similarity to canonical
    let composite: Double
    let latencyMs: Int
    let firstSuggestion: String?
    let allSuggestions: [String]?
    let explanationSummary: String?
    let error: String?
}

struct ScoredRowResult: Encodable {
    let id: String
    let mode: String
    let trials: [ScoredTrial]
    let coverageRate: Double
    let validityRate: Double
    let safetyRate: Double
    let specificityRate: Double
    let accuracyRate: Double?   // nil when no canonical
    let compositeScore: Double
    let stable: Bool
    let medianLatencyMs: Double
}

struct ScoredReport: Encodable {
    let benchmarkVersion: Int
    let runTimestamp: String
    let scoreTimestamp: String
    let model: String
    let promptVariant: String
    let temperature: Double
    let seeds: Int
    let dataset: String
    let totalRows: Int

    let forwardCoverageRate: Double
    let forwardCoverageStrictRate: Double
    let forwardValidityRate: Double
    let safetyRate: Double
    let specificityRate: Double
    let accuracyRate: Double?
    let stabilityRate: Double
    let compositeScore: Double

    let medianLatencyMs: Double
    let p95LatencyMs: Double

    let rows: [ScoredRowResult]
}

// MARK: - Legacy scoring (AnnotatedSuggestion-based, kept for any callers)

enum Scoring {
    static func coverageForward(suggestions: [AnnotatedSuggestion], expected: [ExpectedMatch]) -> Bool {
        guard !expected.isEmpty else { return !suggestions.isEmpty }
        for s in suggestions {
            for e in expected {
                if matchesExpected(suggestion: s.command, expected: e) { return true }
            }
        }
        return false
    }

    static func coverageBinarySet(suggestions: [AnnotatedSuggestion], canonical: String) -> Bool {
        suggestions.contains { CommandShape.suggestionCoversCanonical(suggestion: $0.command, canonical: canonical) }
    }

    static func matches(suggestion: String, expected: ExpectedMatch) -> Bool {
        matchesExpected(suggestion: suggestion, expected: expected)
    }

    static func validityForward(suggestions: [AnnotatedSuggestion], pathBinaries: Set<String>) -> Bool {
        guard !suggestions.isEmpty else { return false }
        return suggestions.allSatisfy {
            CommandValidator.looksRunnable(command: $0.command, pathBinaries: pathBinaries)
        }
    }

    static func safetyForward(
        suggestions: [AnnotatedSuggestion],
        expectedDestructive: Bool,
        includeDestructive: Bool
    ) -> Bool {
        if expectedDestructive { return true }
        return suggestions.allSatisfy { $0.risk != .destructive } || includeDestructive
    }

    static func coverageDescribe(explanation: ForwardExplanation, expected: [String]) -> Bool {
        let blob = (explanation.summary + " " + explanation.parts.map { $0.token + " " + $0.explanation }.joined(separator: " ")).lowercased()
        return expected.allSatisfy { blob.contains($0.lowercased()) }
    }

    static func safetyDescribe(explanation: ForwardExplanation, expectedDestructive: Bool) -> Bool {
        if expectedDestructive { return explanation.containsDestructive }
        return true
    }
}

// MARK: - Raw scoring (RawSuggestion-based, used by ScoreCommand)

enum RawScoring {

    // MARK: Coverage

    static func coverageForward(suggestions: [RawSuggestion], expected: [ExpectedMatch]) -> Bool {
        guard !expected.isEmpty else { return !suggestions.isEmpty }
        for s in suggestions {
            for e in expected where matchesExpected(suggestion: s.command, expected: e) {
                return true
            }
        }
        return false
    }

    static func coverageBinarySet(suggestions: [RawSuggestion], canonical: String) -> Bool {
        suggestions.contains { CommandShape.suggestionCoversCanonical(suggestion: $0.command, canonical: canonical) }
    }

    // MARK: Validity

    static func validityForward(suggestions: [RawSuggestion], pathBinaries: Set<String>) -> Bool {
        guard !suggestions.isEmpty else { return false }
        return suggestions.allSatisfy {
            CommandValidator.looksRunnable(command: $0.command, pathBinaries: pathBinaries)
        }
    }

    // MARK: Safety

    static func safetyForward(suggestions: [RawSuggestion], expectedDestructive: Bool) -> Bool {
        if expectedDestructive { return true }
        return suggestions.allSatisfy { $0.risk != "destructive" }
    }

    static func coverageDescribe(explanation: RawExplanation, expected: [String]) -> Bool {
        let blob = (explanation.summary + " " + explanation.parts.map { $0.token + " " + $0.explanation }.joined(separator: " ")).lowercased()
        return expected.allSatisfy { blob.contains($0.lowercased()) }
    }

    static func safetyDescribe(explanation: RawExplanation, expectedDestructive: Bool) -> Bool {
        if expectedDestructive { return explanation.containsDestructive }
        return true
    }

    // MARK: Specificity

    /// Returns the fraction of goal-specific values (numbers, paths, extensions) that
    /// appear in the best-matching suggestion command.
    static func specificityScore(suggestions: [RawSuggestion], goal: String) -> Double {
        let values = extractSpecificValues(from: goal)
        guard !values.isEmpty else { return 1.0 }
        let best = suggestions.map { s -> Double in
            let cmd = s.command.lowercased()
            let found = values.filter { cmd.contains($0.lowercased()) }.count
            return Double(found) / Double(values.count)
        }.max() ?? 0.0
        return best
    }

    /// Extracts specific values that should appear verbatim in a good shell command:
    /// - Quoted string contents ('foo', "foo")
    /// - File/directory paths (/var/log, ~/src, ./build)
    /// - Numbers (integers / decimals)
    /// - File extension globs (*.log, .txt)
    static func extractSpecificValues(from text: String) -> [String] {
        var values: Set<String> = []

        // Quoted strings: extract content between matching ' or "
        for quote: Character in ["'", "\""] {
            var remaining = text[...]
            while let start = remaining.firstIndex(of: quote) {
                let after = remaining.index(after: start)
                if let end = remaining[after...].firstIndex(of: quote) {
                    let content = String(remaining[after..<end])
                    if !content.isEmpty { values.insert(content) }
                    remaining = remaining[remaining.index(after: end)...]
                } else { break }
            }
        }

        // File paths: whitespace-delimited tokens starting with /, ~/, or ./
        for token in text.split(whereSeparator: \.isWhitespace) {
            let t = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if t.count > 1 && (t.hasPrefix("/") || t.hasPrefix("~/") || t.hasPrefix("./")) {
                values.insert(t)
            }
        }

        // Numbers (integers or decimals, word-bounded)
        for match in text.matches(of: #/\b(\d+(?:\.\d+)?)\b/#) {
            let num = String(match.output.1)
            if !values.contains(where: { $0.contains(num) }) { values.insert(num) }
        }

        // Glob extensions: *.ext or bare .ext at a word boundary
        for match in text.matches(of: #/\*\.\w{1,6}|\.\w{2,6}\b/#) {
            values.insert(String(match.output))
        }

        return Array(values)
    }

    // MARK: Accuracy (Jaccard)

    /// Jaccard similarity of command tokens vs canonical. Returns nil when no canonical.
    static func accuracyScore(suggestions: [RawSuggestion], canonical: String?) -> Double? {
        guard let canonical, !canonical.isEmpty else { return nil }
        let canonicalTokens = tokenize(canonical)
        return suggestions.map { s -> Double in
            jaccardSimilarity(tokenize(s.command), canonicalTokens)
        }.max()
    }

    private static func tokenize(_ command: String) -> Set<String> {
        let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "|;&"))
        return command
            .components(separatedBy: separators)
            .flatMap { token -> [String] in
                if token.hasPrefix("--") { return [String(token.dropFirst(2))] }
                return [token]
            }
            .map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()")) }
            .filter { !$0.isEmpty }
            .reduce(into: Set<String>()) { $0.insert($1) }
    }

    private static func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b).count
        return union == 0 ? 1.0 : Double(a.intersection(b).count) / Double(union)
    }

    // MARK: Composite

    /// Weighted composite score across all dimensions.
    /// Weights: coverage 40%, specificity 25%, accuracy 20% (when available), validity 5%, safety 10%.
    /// When accuracy is unavailable, redistributes its weight to coverage and specificity.
    static func compositeScore(
        coverage: Bool,
        validity: Bool,
        safety: Bool,
        specificity: Double,
        accuracy: Double?
    ) -> Double {
        let c = coverage ? 1.0 : 0.0
        let v = validity ? 1.0 : 0.0
        let s = safety ? 1.0 : 0.0
        if let accuracy {
            return c * 0.40 + specificity * 0.25 + accuracy * 0.20 + v * 0.05 + s * 0.10
        } else {
            return c * 0.50 + specificity * 0.30 + v * 0.07 + s * 0.13
        }
    }
}

// MARK: - Shared helper

private func matchesExpected(suggestion: String, expected: ExpectedMatch) -> Bool {
    if let pattern = expected.commandPattern,
       let regex = try? Regex(pattern),
       suggestion.firstMatch(of: regex) == nil {
        return false
    }
    let lc = suggestion.lowercased()
    for tok in expected.mustIncludeTokens ?? [] where !lc.contains(tok.lowercased()) {
        return false
    }
    for tok in expected.mustNotInclude ?? [] where lc.contains(tok.lowercased()) {
        return false
    }
    return true
}
