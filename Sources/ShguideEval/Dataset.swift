import Foundation

struct ExpectedMatch: Codable {
    let commandPattern: String?
    let mustIncludeTokens: [String]?
    let mustNotInclude: [String]?

    enum CodingKeys: String, CodingKey {
        case commandPattern = "command_pattern"
        case mustIncludeTokens = "must_include_tokens"
        case mustNotInclude = "must_not_include"
    }
}

struct EvalRow: Decodable {
    let id: String
    let mode: String
    let goal: String?
    let command: String?
    let canonicalCommand: String?
    let expectedAnyOf: [ExpectedMatch]?
    let expectedSummaryContains: [String]?
    let destructive: Bool

    enum CodingKeys: String, CodingKey {
        case id, mode, goal, command, destructive
        case canonicalCommand = "canonical_command"
        case expectedAnyOf = "expected_any_of"
        case expectedSummaryContains = "expected_summary_contains"
    }
}

enum Dataset {
    static func load(from url: URL) throws -> [EvalRow] {
        try loadWithVersion(from: url).0
    }

    /// Loads rows and extracts `benchmark_version` from the first comment line.
    /// Expected header format: `// {"benchmark_version": 2, ...}`
    static func loadWithVersion(from url: URL) throws -> ([EvalRow], Int) {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        let decoder = JSONDecoder()
        var rows: [EvalRow] = []
        var benchmarkVersion = 1
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("//") {
                let jsonPart = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if let d = jsonPart.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let v = obj["benchmark_version"] as? Int {
                    benchmarkVersion = v
                }
                continue
            }
            guard let lineData = line.data(using: .utf8) else { continue }
            let row = try decoder.decode(EvalRow.self, from: lineData)
            rows.append(row)
        }
        return (rows, benchmarkVersion)
    }
}
