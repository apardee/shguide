import Foundation

struct ExpectedMatch: Decodable {
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
    let expectedAnyOf: [ExpectedMatch]?
    let expectedSummaryContains: [String]?
    let destructive: Bool

    enum CodingKeys: String, CodingKey {
        case id, mode, goal, command, destructive
        case expectedAnyOf = "expected_any_of"
        case expectedSummaryContains = "expected_summary_contains"
    }
}

enum Dataset {
    static func load(from url: URL) throws -> [EvalRow] {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        let decoder = JSONDecoder()
        var rows: [EvalRow] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }
            guard let lineData = line.data(using: .utf8) else { continue }
            let row = try decoder.decode(EvalRow.self, from: lineData)
            rows.append(row)
        }
        return rows
    }
}
