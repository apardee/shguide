import ArgumentParser
import Foundation
import ShguideCore

@available(macOS 26.0, *)
struct ScoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "score",
        abstract: "Score a raw JSONL run output and emit a structured report."
    )

    @Option(name: .customLong("input"), help: "Path to raw JSONL produced by 'run'.")
    var input: String

    @Option(name: .customLong("report"), help: "Path to write scored JSON report. Omit to print to stdout.")
    var report: String?

    @Flag(name: .customLong("update-history"), help: "Append a summary row to the benchmark history file.")
    var updateHistory: Bool = false

    @Option(name: .customLong("history-file"), help: "Path to BENCHMARK_HISTORY.md (default: docs/BENCHMARK_HISTORY.md).")
    var historyFile: String = "docs/BENCHMARK_HISTORY.md"

    func run() async throws {
        let rawResults = try loadRawResults(from: URL(fileURLWithPath: input))
        guard !rawResults.isEmpty else {
            throw ValidationError("No rows found in \(input)")
        }

        let pathBinaries = PathInventory.snapshot()
        let scoreTimestamp = ISO8601DateFormatter().string(from: Date())

        let scoredRows = rawResults.map { row in
            scoreRow(row: row, pathBinaries: pathBinaries)
        }

        let scored = aggregate(rows: scoredRows, raw: rawResults, scoreTimestamp: scoreTimestamp)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(scored)
        if let report {
            try data.write(to: URL(fileURLWithPath: report))
            stderr("Wrote report to \(report)")
        } else {
            print(String(decoding: data, as: UTF8.self))
        }

        printRollup(scored)

        if updateHistory {
            try appendHistory(scored)
        }
    }

    // MARK: - Row scoring

    private func scoreRow(row: RawRowResult, pathBinaries: Set<String>) -> ScoredRowResult {
        let trials = row.trials.map { trial in
            scoreTrial(trial: trial, row: row, pathBinaries: pathBinaries)
        }
        let n = Double(trials.count)
        let coverageRate = n == 0 ? 0 : Double(trials.filter(\.coverage).count) / n
        let validityRate = n == 0 ? 0 : Double(trials.filter(\.validity).count) / n
        let safetyRate = n == 0 ? 0 : Double(trials.filter(\.safety).count) / n
        let specificityRate = n == 0 ? 0 : trials.map(\.specificity).reduce(0, +) / n
        let accuracyValues = trials.compactMap(\.accuracy)
        let accuracyRate: Double? = accuracyValues.isEmpty ? nil : accuracyValues.reduce(0, +) / Double(accuracyValues.count)
        let compositeScore = n == 0 ? 0 : trials.map(\.composite).reduce(0, +) / n
        let firstCoverage = trials.first?.coverage
        let stable = trials.allSatisfy { $0.coverage == firstCoverage }
        let latencies = trials.map(\.latencyMs).sorted()
        let medianLatency = latencies.isEmpty ? 0 : Double(latencies[latencies.count / 2])
        return ScoredRowResult(
            id: row.id,
            mode: row.mode,
            trials: trials,
            coverageRate: coverageRate,
            validityRate: validityRate,
            safetyRate: safetyRate,
            specificityRate: specificityRate,
            accuracyRate: accuracyRate,
            compositeScore: compositeScore,
            stable: stable,
            medianLatencyMs: medianLatency
        )
    }

    private func scoreTrial(trial: RawTrial, row: RawRowResult, pathBinaries: Set<String>) -> ScoredTrial {
        guard trial.error == nil else {
            return ScoredTrial(seed: trial.seed, coverage: false, validity: false, safety: !row.destructive,
                               specificity: 0, accuracy: nil, composite: 0,
                               latencyMs: trial.latencyMs, firstSuggestion: nil,
                               allSuggestions: nil, explanationSummary: nil, error: trial.error)
        }
        switch row.mode {
        case "forward":
            let suggestions = trial.suggestions ?? []
            let coverage: Bool
            if let canonical = row.canonicalCommand {
                coverage = RawScoring.coverageBinarySet(suggestions: suggestions, canonical: canonical)
            } else {
                coverage = RawScoring.coverageForward(suggestions: suggestions, expected: row.expectedAnyOf ?? [])
            }
            let validity = RawScoring.validityForward(suggestions: suggestions, pathBinaries: pathBinaries)
            let safety = RawScoring.safetyForward(suggestions: suggestions, expectedDestructive: row.destructive)
            let specificity = RawScoring.specificityScore(suggestions: suggestions, goal: row.goal ?? "")
            let accuracy = RawScoring.accuracyScore(suggestions: suggestions, canonical: row.canonicalCommand)
            let composite = RawScoring.compositeScore(coverage: coverage, validity: validity,
                                                       safety: safety, specificity: specificity,
                                                       accuracy: accuracy)
            return ScoredTrial(seed: trial.seed, coverage: coverage, validity: validity, safety: safety,
                               specificity: specificity, accuracy: accuracy, composite: composite,
                               latencyMs: trial.latencyMs,
                               firstSuggestion: suggestions.first?.command,
                               allSuggestions: suggestions.isEmpty ? nil : suggestions.map(\.command),
                               explanationSummary: nil, error: nil)
        case "describe":
            let exp = trial.explanation
            let coverage = exp.map { RawScoring.coverageDescribe(explanation: $0, expected: row.expectedSummaryContains ?? []) } ?? false
            let safety = exp.map { RawScoring.safetyDescribe(explanation: $0, expectedDestructive: row.destructive) } ?? !row.destructive
            let composite = RawScoring.compositeScore(coverage: coverage, validity: true, safety: safety,
                                                       specificity: 1.0, accuracy: nil)
            return ScoredTrial(seed: trial.seed, coverage: coverage, validity: true, safety: safety,
                               specificity: 1.0, accuracy: nil, composite: composite,
                               latencyMs: trial.latencyMs, firstSuggestion: nil, allSuggestions: nil,
                               explanationSummary: exp?.summary, error: nil)
        default:
            return ScoredTrial(seed: trial.seed, coverage: false, validity: false, safety: true,
                               specificity: 0, accuracy: nil, composite: 0,
                               latencyMs: trial.latencyMs, firstSuggestion: nil,
                               allSuggestions: nil, explanationSummary: nil, error: "unknown mode")
        }
    }

    // MARK: - Aggregation

    private func aggregate(rows: [ScoredRowResult], raw: [RawRowResult], scoreTimestamp: String) -> ScoredReport {
        let forwardRows = rows.filter { $0.mode == "forward" }
        let allTrials = rows.flatMap(\.trials)
        let forwardTrials = forwardRows.flatMap(\.trials)

        let latencies = allTrials.map(\.latencyMs).sorted()
        let medianMs = latencies.isEmpty ? 0.0 : Double(latencies[latencies.count / 2])
        let p95Idx = latencies.isEmpty ? 0 : Int(Double(latencies.count - 1) * 0.95)
        let p95Ms = latencies.isEmpty ? 0.0 : Double(latencies[p95Idx])

        let forwardCoverage = rate(forwardTrials.map(\.coverage))
        let forwardCoverageStrict = forwardRows.isEmpty ? 0.0
            : Double(forwardRows.filter { $0.coverageRate >= 1.0 }.count) / Double(forwardRows.count)
        let forwardValidity = rate(forwardTrials.map(\.validity))
        let safety = rate(allTrials.map(\.safety))
        let specificity = forwardTrials.isEmpty ? 0.0
            : forwardTrials.map(\.specificity).reduce(0, +) / Double(forwardTrials.count)
        let accuracyValues = forwardTrials.compactMap(\.accuracy)
        let accuracyRate: Double? = accuracyValues.isEmpty ? nil
            : accuracyValues.reduce(0, +) / Double(accuracyValues.count)
        let stability = rows.isEmpty ? 0.0
            : Double(rows.filter(\.stable).count) / Double(rows.count)
        let composite = allTrials.isEmpty ? 0.0
            : allTrials.map(\.composite).reduce(0, +) / Double(allTrials.count)

        let first = raw.first
        return ScoredReport(
            benchmarkVersion: first?.benchmarkVersion ?? 1,
            runTimestamp: first?.runTimestamp ?? "",
            scoreTimestamp: scoreTimestamp,
            model: first?.model ?? "",
            promptVariant: first?.promptVariant ?? "",
            temperature: first?.temperature ?? 0,
            seeds: (raw.first?.trials.count) ?? 0,
            dataset: URL(fileURLWithPath: input).lastPathComponent,
            totalRows: rows.count,
            forwardCoverageRate: forwardCoverage,
            forwardCoverageStrictRate: forwardCoverageStrict,
            forwardValidityRate: forwardValidity,
            safetyRate: safety,
            specificityRate: specificity,
            accuracyRate: accuracyRate,
            stabilityRate: stability,
            compositeScore: composite,
            medianLatencyMs: medianMs,
            p95LatencyMs: p95Ms,
            rows: rows
        )
    }

    private func rate(_ bools: [Bool]) -> Double {
        bools.isEmpty ? 0 : Double(bools.filter { $0 }.count) / Double(bools.count)
    }

    // MARK: - I/O

    private func loadRawResults(from url: URL) throws -> [RawRowResult] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        var results: [RawRowResult] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }
            guard let data = line.data(using: .utf8) else { continue }
            let row = try decoder.decode(RawRowResult.self, from: data)
            results.append(row)
        }
        return results
    }

    // MARK: - Human-readable rollup

    private func printRollup(_ r: ScoredReport) {
        let pct = { (v: Double) in String(format: "%.1f%%", v * 100) }
        let pctOpt = { (v: Double?) in v.map { String(format: "%.1f%%", $0 * 100) } ?? "  n/a" }
        stderr("""

        === \(r.model) | \(r.dataset) | \(r.totalRows) rows × \(r.seeds) seeds | variant=\(r.promptVariant) T=\(String(format: "%.2f", r.temperature)) ===
          coverage:        \(pct(r.forwardCoverageRate))  (mean over trials)
          coverage strict: \(pct(r.forwardCoverageStrictRate))  (all trials pass)
          validity:        \(pct(r.forwardValidityRate))
          safety:          \(pct(r.safetyRate))
          specificity:     \(pct(r.specificityRate))  (goal values in command)
          accuracy:        \(pctOpt(r.accuracyRate))  (Jaccard vs canonical)
          stability:       \(pct(r.stabilityRate))  (rows where all trials agreed)
          composite score: \(pct(r.compositeScore))
          median latency:  \(String(format: "%.0fms", r.medianLatencyMs))
          p95 latency:     \(String(format: "%.0fms", r.p95LatencyMs))

        """)
    }

    // MARK: - History append

    private func appendHistory(_ r: ScoredReport) throws {
        let pct = { (v: Double) in String(format: "%.1f%%", v * 100) }
        let pctOpt = { (v: Double?) in v.map { String(format: "%.1f%%", $0 * 100) } ?? "n/a" }
        let date = String(r.scoreTimestamp.prefix(10))
        let row = "| \(date) | v\(r.benchmarkVersion) | \(r.model) | \(r.promptVariant) | \(String(format: "%.2f", r.temperature)) | \(r.totalRows) | \(pct(r.forwardCoverageRate)) | \(pct(r.forwardValidityRate)) | \(pct(r.safetyRate)) | \(pct(r.specificityRate)) | \(pctOpt(r.accuracyRate)) | \(pct(r.compositeScore)) | \(String(format: "%.0f", r.medianLatencyMs))ms |"
        let path = URL(fileURLWithPath: historyFile)
        guard var contents = try? String(contentsOf: path, encoding: .utf8) else {
            throw ValidationError("Could not read history file at \(historyFile)")
        }
        if !contents.hasSuffix("\n") { contents += "\n" }
        contents += row + "\n"
        try contents.write(to: path, atomically: true, encoding: .utf8)
        stderr("Appended history row to \(historyFile)")
    }

    private func stderr(_ msg: String) {
        FileHandle.standardError.write(Data((msg + "\n").utf8))
    }
}
