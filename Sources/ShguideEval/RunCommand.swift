import ArgumentParser
import Foundation
import ShguideCore

enum Strategy: String, ExpressibleByArgument, CaseIterable {
    case mock
    case generableOnly = "generable-only"
    case generableWithTools = "generable-with-tools"
}

@available(macOS 26.0, *)
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the eval dataset and emit a JSON report."
    )

    @Option(name: .customLong("dataset"), help: "Path to the JSONL dataset.")
    var dataset: String

    @Option(name: .customLong("strategy"), help: "Engine strategy to evaluate.")
    var strategy: Strategy = .generableWithTools

    @Option(name: .customLong("report"), help: "Path to write the JSON report. If omitted, prints to stdout.")
    var report: String?

    @Option(name: .customLong("limit"), help: "Optional cap on number of rows to run.")
    var limit: Int?

    @Flag(name: .customLong("include-destructive"), help: "Pass through to the engine.")
    var includeDestructive: Bool = false

    func run() async throws {
        let url = URL(fileURLWithPath: dataset)
        let rows = try Dataset.load(from: url)
        let chosen = limit.map { Array(rows.prefix($0)) } ?? rows
        let pathBinaries = PathInventory.snapshot()
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        var results: [RowResult] = []
        for row in chosen {
            let started = Date()
            do {
                let result = try await evaluate(row: row, pathBinaries: pathBinaries, osVersion: osVersion)
                results.append(RowResult(
                    id: row.id,
                    mode: row.mode,
                    coverage: result.coverage,
                    validity: result.validity,
                    safety: result.safety,
                    latencySeconds: Date().timeIntervalSince(started),
                    suggestionsReturned: result.count,
                    firstSuggestion: result.firstSuggestion,
                    allSuggestions: result.allSuggestions.isEmpty ? nil : result.allSuggestions,
                    explanationSummary: result.explanationSummary,
                    error: nil
                ))
            } catch {
                results.append(RowResult(
                    id: row.id,
                    mode: row.mode,
                    coverage: false,
                    validity: false,
                    safety: !row.destructive,
                    latencySeconds: Date().timeIntervalSince(started),
                    suggestionsReturned: 0,
                    firstSuggestion: nil,
                    allSuggestions: nil,
                    explanationSummary: nil,
                    error: String(describing: error)
                ))
            }
            FileHandle.standardError.write(Data("[\(results.count)/\(chosen.count)] \(row.id) \(results.last!.coverage ? "✓" : "✗")\n".utf8))
        }

        let aggregate = aggregate(rows: results, datasetName: url.lastPathComponent)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(aggregate)
        if let report {
            try data.write(to: URL(fileURLWithPath: report))
            FileHandle.standardError.write(Data("Wrote \(report)\n".utf8))
        } else {
            print(String(decoding: data, as: UTF8.self))
        }
        printRollup(aggregate)
    }

    private struct PerRow {
        let coverage: Bool
        let validity: Bool
        let safety: Bool
        let count: Int
        let firstSuggestion: String?
        let allSuggestions: [String]
        let explanationSummary: String?
    }

    private func evaluate(row: EvalRow, pathBinaries: Set<String>, osVersion: String) async throws -> PerRow {
        let context = InvocationContext(
            shellName: "zsh",
            osVersion: osVersion,
            pathBinaries: pathBinaries,
            historyMatches: [],
            includeDestructive: includeDestructive,
            useTools: strategy == .generableWithTools
        )

        let engine: any QueryEngine
        switch strategy {
        case .mock: engine = MockEngine()
        case .generableOnly: engine = FoundationModelsEngine(useTools: false)
        case .generableWithTools: engine = FoundationModelsEngine(useTools: true)
        }

        switch row.mode {
        case "forward":
            guard let goal = row.goal else { throw EvalError.malformedRow(row.id) }
            let suggestions = try await engine.forward(goal: goal, context: context)
            let coverage = Scoring.coverageForward(suggestions: suggestions, expected: row.expectedAnyOf ?? [])
            let validity = Scoring.validityForward(suggestions: suggestions, pathBinaries: pathBinaries)
            let safety = Scoring.safetyForward(
                suggestions: suggestions,
                expectedDestructive: row.destructive,
                includeDestructive: includeDestructive
            )
            return PerRow(coverage: coverage, validity: validity, safety: safety,
                          count: suggestions.count, firstSuggestion: suggestions.first?.command,
                          allSuggestions: suggestions.map(\.command), explanationSummary: nil)
        case "describe":
            guard let cmd = row.command else { throw EvalError.malformedRow(row.id) }
            let exp = try await engine.describe(command: cmd, context: context)
            let coverage = Scoring.coverageDescribe(explanation: exp, expected: row.expectedSummaryContains ?? [])
            let safety = Scoring.safetyDescribe(explanation: exp, expectedDestructive: row.destructive)
            return PerRow(coverage: coverage, validity: true, safety: safety, count: exp.parts.count,
                          firstSuggestion: nil, allSuggestions: [], explanationSummary: exp.summary)
        default:
            throw EvalError.malformedRow(row.id)
        }
    }

    private func aggregate(rows: [RowResult], datasetName: String) -> AggregateReport {
        let forwardRows = rows.filter { $0.mode == "forward" }
        let latencies = rows.map(\.latencySeconds).sorted()
        let median = latencies.isEmpty ? 0 : latencies[latencies.count / 2]
        let p95Idx = latencies.isEmpty ? 0 : Int(Double(latencies.count - 1) * 0.95)
        let p95 = latencies.isEmpty ? 0 : latencies[p95Idx]
        func rate(_ pred: (RowResult) -> Bool, in subset: [RowResult]) -> Double {
            subset.isEmpty ? 0 : Double(subset.filter(pred).count) / Double(subset.count)
        }
        return AggregateReport(
            dataset: datasetName,
            strategy: strategy.rawValue,
            totalRows: rows.count,
            forwardCoverageRate: rate({ $0.coverage }, in: forwardRows),
            forwardValidityRate: rate({ $0.validity }, in: forwardRows),
            safetyRate: rate({ $0.safety }, in: rows),
            medianLatencySeconds: median,
            p95LatencySeconds: p95,
            rows: rows
        )
    }

    private func printRollup(_ r: AggregateReport) {
        let pct = { (v: Double) in String(format: "%.1f%%", v * 100) }
        FileHandle.standardError.write(Data("""

        === \(r.strategy) on \(r.dataset) (\(r.totalRows) rows) ===
          coverage:  \(pct(r.forwardCoverageRate))  (forward rows only)
          validity:  \(pct(r.forwardValidityRate))
          safety:    \(pct(r.safetyRate))
          median latency: \(String(format: "%.2fs", r.medianLatencySeconds))
          p95 latency:    \(String(format: "%.2fs", r.p95LatencySeconds))

        """.utf8))
    }

    enum EvalError: Error, CustomStringConvertible {
        case malformedRow(String)
        var description: String {
            switch self {
            case .malformedRow(let id): return "malformed row: \(id)"
            }
        }
    }
}
