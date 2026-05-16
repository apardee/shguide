import Foundation

struct EvalRow: Decodable {
    let id: String
    let mode: String     // "forward" | "describe"
    let goal: String?    // forward mode
    let command: String? // describe mode
}

enum Dataset {
    static func load(from url: URL) throws -> [EvalRow] {
        try loadWithVersion(from: url).0
    }

    /// Loads rows and reads `benchmark_version` from the first comment line.
    /// Expected header: `// {"benchmark_version": 3}`
    static func loadWithVersion(from url: URL) throws -> ([EvalRow], Int) {
        let text = try String(contentsOf: url, encoding: .utf8)
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
            rows.append(try decoder.decode(EvalRow.self, from: lineData))
        }
        return (rows, benchmarkVersion)
    }
}
