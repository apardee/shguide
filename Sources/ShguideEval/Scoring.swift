import Foundation
import ShguideCore

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

enum Scoring {
    static func coverageForward(suggestions: [AnnotatedSuggestion], expected: [ExpectedMatch]) -> Bool {
        guard !expected.isEmpty else { return !suggestions.isEmpty }
        for s in suggestions {
            for e in expected {
                if matches(suggestion: s.command, expected: e) { return true }
            }
        }
        return false
    }

    /// Pass if any suggestion's binary shape covers the canonical's.
    static func coverageBinarySet(suggestions: [AnnotatedSuggestion], canonical: String) -> Bool {
        suggestions.contains { CommandShape.suggestionCoversCanonical(suggestion: $0.command, canonical: canonical) }
    }

    static func matches(suggestion: String, expected: ExpectedMatch) -> Bool {
        if let pattern = expected.commandPattern,
           let regex = try? NSRegularExpression(pattern: pattern),
           regex.firstMatch(in: suggestion, range: NSRange(suggestion.startIndex..., in: suggestion)) == nil {
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
