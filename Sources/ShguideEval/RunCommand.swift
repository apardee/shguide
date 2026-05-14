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
    var strategy: Strategy = .generableOnly

    @Option(name: .customLong("report"), help: "Path to write the JSON report. If omitted, prints to stdout.")
    var report: String?

    @Option(name: .customLong("limit"), help: "Optional cap on number of rows to run.")
    var limit: Int?

    @Option(name: .customLong("seeds"), help: "Number of independent trials per row (>=1). Higher exposes run-to-run variance.")
    var seeds: Int = 1

    @Option(name: .customLong("temperature"), help: "Sampling temperature for the model. 0.0 is deterministic; 0.2 is the ship default.")
    var temperature: Double = 0.2

    @Flag(name: .customLong("include-destructive"), help: "Pass through to the engine.")
    var includeDestructive: Bool = false

    func run() async throws {
        guard seeds >= 1 else {
            throw ValidationError("--seeds must be >= 1")
        }
        let url = URL(fileURLWithPath: dataset)
        let rows = try Dataset.load(from: url)
        let chosen = limit.map { Array(rows.prefix($0)) } ?? rows
        let pathBinaries = PathInventory.snapshot()
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        var results: [RowResult] = []
        for (idx, row) in chosen.enumerated() {
            var trials: [Trial] = []
            for _ in 0..<seeds {
                let started = Date()
                do {
                    let result = try await evaluateWithRetry(row: row, pathBinaries: pathBinaries, osVersion: osVersion)
                    trials.append(Trial(
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
                    trials.append(Trial(
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
            }
            let rowResult = makeRowResult(id: row.id, mode: row.mode, trials: trials)
            results.append(rowResult)
            let glyphs = trials.map { $0.coverage ? "✓" : "✗" }.joined()
            FileHandle.standardError.write(Data("[\(idx + 1)/\(chosen.count)] \(row.id) \(glyphs)\n".utf8))
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

    private struct PerTrial {
        let coverage: Bool
        let validity: Bool
        let safety: Bool
        let count: Int
        let firstSuggestion: String?
        let allSuggestions: [String]
        let explanationSummary: String?
    }

    private func evaluateWithRetry(row: EvalRow, pathBinaries: Set<String>, osVersion: String) async throws -> PerTrial {
        let backoffs: [UInt64] = [500_000_000, 1_500_000_000, 4_000_000_000]
        var lastError: Error?
        for attempt in 0...backoffs.count {
            do {
                return try await evaluate(row: row, pathBinaries: pathBinaries, osVersion: osVersion)
            } catch {
                lastError = error
                if !isTransientServiceError(error) || attempt == backoffs.count { throw error }
                try? await Task.sleep(nanoseconds: backoffs[attempt])
            }
        }
        throw lastError ?? EvalError.malformedRow(row.id)
    }

    private func isTransientServiceError(_ error: Error) -> Bool {
        let s = String(describing: error)
        return s.contains("ModelManagerError Code=1013") || s.contains("ModelManagerError Code=1014")
    }

    private func evaluate(row: EvalRow, pathBinaries: Set<String>, osVersion: String) async throws -> PerTrial {
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
        case .generableOnly: engine = FoundationModelsEngine(useTools: false, temperature: temperature)
        case .generableWithTools: engine = FoundationModelsEngine(useTools: true, temperature: temperature)
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
            return PerTrial(coverage: coverage, validity: validity, safety: safety,
                            count: suggestions.count, firstSuggestion: suggestions.first?.command,
                            allSuggestions: suggestions.map(\.command), explanationSummary: nil)
        case "describe":
            guard let cmd = row.command else { throw EvalError.malformedRow(row.id) }
            let exp = try await engine.describe(command: cmd, context: context)
            let coverage = Scoring.coverageDescribe(explanation: exp, expected: row.expectedSummaryContains ?? [])
            let safety = Scoring.safetyDescribe(explanation: exp, expectedDestructive: row.destructive)
            return PerTrial(coverage: coverage, validity: true, safety: safety, count: exp.parts.count,
                            firstSuggestion: nil, allSuggestions: [], explanationSummary: exp.summary)
        default:
            throw EvalError.malformedRow(row.id)
        }
    }

    private func makeRowResult(id: String, mode: String, trials: [Trial]) -> RowResult {
        let n = Double(trials.count)
        let coverageRate = n == 0 ? 0 : Double(trials.filter(\.coverage).count) / n
        let validityRate = n == 0 ? 0 : Double(trials.filter(\.validity).count) / n
        let safetyRate = n == 0 ? 0 : Double(trials.filter(\.safety).count) / n
        let firstCoverage = trials.first?.coverage
        let stable = trials.allSatisfy { $0.coverage == firstCoverage }
        let latencies = trials.map(\.latencySeconds).sorted()
        let median = latencies.isEmpty ? 0 : latencies[latencies.count / 2]
        return RowResult(
            id: id,
            mode: mode,
            trials: trials,
            coverageRate: coverageRate,
            validityRate: validityRate,
            safetyRate: safetyRate,
            stable: stable,
            medianLatencySeconds: median
        )
    }

    private func aggregate(rows: [RowResult], datasetName: String) -> AggregateReport {
        let forwardRows = rows.filter { $0.mode == "forward" }
        let forwardTrials = forwardRows.flatMap(\.trials)
        let allTrials = rows.flatMap(\.trials)
        let latencies = allTrials.map(\.latencySeconds).sorted()
        let median = latencies.isEmpty ? 0 : latencies[latencies.count / 2]
        let p95Idx = latencies.isEmpty ? 0 : Int(Double(latencies.count - 1) * 0.95)
        let p95 = latencies.isEmpty ? 0 : latencies[p95Idx]
        let forwardCoverageRate = forwardTrials.isEmpty
            ? 0 : Double(forwardTrials.filter(\.coverage).count) / Double(forwardTrials.count)
        let forwardCoverageStrictRate = forwardRows.isEmpty
            ? 0 : Double(forwardRows.filter { $0.coverageRate >= 1.0 }.count) / Double(forwardRows.count)
        let forwardValidityRate = forwardTrials.isEmpty
            ? 0 : Double(forwardTrials.filter(\.validity).count) / Double(forwardTrials.count)
        let safetyRate = allTrials.isEmpty
            ? 0 : Double(allTrials.filter(\.safety).count) / Double(allTrials.count)
        let stabilityRate = rows.isEmpty
            ? 0 : Double(rows.filter(\.stable).count) / Double(rows.count)
        return AggregateReport(
            dataset: datasetName,
            strategy: strategy.rawValue,
            temperature: temperature,
            seeds: seeds,
            totalRows: rows.count,
            forwardCoverageRate: forwardCoverageRate,
            forwardCoverageStrictRate: forwardCoverageStrictRate,
            forwardValidityRate: forwardValidityRate,
            safetyRate: safetyRate,
            stabilityRate: stabilityRate,
            medianLatencySeconds: median,
            p95LatencySeconds: p95,
            rows: rows
        )
    }

    private func printRollup(_ r: AggregateReport) {
        let pct = { (v: Double) in String(format: "%.1f%%", v * 100) }
        FileHandle.standardError.write(Data("""

        === \(r.strategy) on \(r.dataset) (\(r.totalRows) rows × \(r.seeds) seeds, T=\(String(format: "%.2f", r.temperature))) ===
          coverage:        \(pct(r.forwardCoverageRate))  (mean over trials)
          coverage strict: \(pct(r.forwardCoverageStrictRate))  (all trials pass)
          validity:        \(pct(r.forwardValidityRate))
          safety:          \(pct(r.safetyRate))
          stability:       \(pct(r.stabilityRate))  (rows where all trials agreed)
          median latency:  \(String(format: "%.2fs", r.medianLatencySeconds))
          p95 latency:     \(String(format: "%.2fs", r.p95LatencySeconds))

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
