import Foundation

struct RawSuggestion: Codable, Sendable {
    let command: String
    let explanation: String
    let risk: String        // "safe" | "caution" | "destructive"
    let fromHistory: Bool
}

struct RawExplanationPart: Codable, Sendable {
    let token: String
    let explanation: String
}

struct RawExplanation: Codable, Sendable {
    let summary: String
    let parts: [RawExplanationPart]
    let containsDestructive: Bool
}

/// One seed's output for a single eval row.
struct RawTrial: Codable, Sendable {
    let seed: Int
    let suggestions: [RawSuggestion]?  // forward mode
    let explanation: RawExplanation?   // describe mode
    let latencyMs: Int
    let timestamp: String
    let error: String?
}

/// All trials for a single eval row. Written as one JSONL line per row.
struct RawRowResult: Codable, Sendable {
    // Input (mirrored from EvalRow for self-contained scoring)
    let id: String
    let mode: String
    let goal: String?
    let command: String?
    let canonicalCommand: String?
    let expectedAnyOf: [ExpectedMatch]?
    let expectedSummaryContains: [String]?
    let destructive: Bool

    // Run metadata
    let model: String
    let promptVariant: String
    let temperature: Double
    let benchmarkVersion: Int
    let runTimestamp: String

    let trials: [RawTrial]

    enum CodingKeys: String, CodingKey {
        case id, mode, goal, command, destructive, model, temperature, trials
        case canonicalCommand = "canonical_command"
        case expectedAnyOf = "expected_any_of"
        case expectedSummaryContains = "expected_summary_contains"
        case promptVariant = "prompt_variant"
        case benchmarkVersion = "benchmark_version"
        case runTimestamp = "run_timestamp"
    }
}
