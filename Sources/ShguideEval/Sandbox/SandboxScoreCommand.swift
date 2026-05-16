import ArgumentParser
import Foundation
import ShguideCore

/// `shguide-eval sandbox-score --input raw.jsonl [--report report.json]`
///
/// Reads the raw JSONL produced by `shguide-eval run`, finds every row that
/// has a registered `SandboxTestCase`, runs each trial's best suggestion
/// inside a Seatbelt sandbox, and emits a `SandboxReport`.
///
/// Rows with no matching test case are included in the output with
/// `tested: false` so overall row counts stay consistent.
@available(macOS 26.0, *)
struct SandboxScoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sandbox-score",
        abstract: "Execute model suggestions in a Seatbelt sandbox and score the results."
    )

    @Option(name: .customLong("input"), help: "Path to raw JSONL produced by 'run'.")
    var input: String

    @Option(name: .customLong("report"), help: "Path to write the sandbox JSON report (default: stdout).")
    var report: String?

    @Option(name: .customLong("timeout"), help: "Per-command timeout in seconds (default: 10).")
    var timeout: Double = 10.0

    @Flag(name: .customLong("verbose"), help: "Print per-row results to stderr as they complete.")
    var verbose: Bool = false

    // MARK: - Entry point

    func run() async throws {
        let rawResults = try loadRawResults(from: URL(fileURLWithPath: input))
        guard !rawResults.isEmpty else {
            throw ValidationError("No rows found in \(input)")
        }
        stderr("sandbox-score: \(rawResults.count) rows, timeout=\(timeout)s")

        var sandboxRows: [SandboxRowResult] = []
        var allExecutable: [Bool] = []
        var allCorrect: [Bool] = []

        for row in rawResults {
            let result = await scoreRow(row)
            sandboxRows.append(result)
            if result.tested {
                allExecutable.append(contentsOf: result.trials.map(\.executable))
                allCorrect.append(contentsOf: result.trials.compactMap(\.correct))
            }
            if verbose {
                let tag = result.tested ? (result.executableRate >= 1.0 ? "✓" : "✗") : "–"
                stderr("  \(tag) \(row.id)")
                for t in result.trials where result.tested {
                    let cTag = t.correct == true ? "correct" : (t.correct == false ? "WRONG" : "n/a")
                    stderr("      seed=\(t.seed) exec=\(t.executable) \(cTag) \(t.note.isEmpty ? "" : "[\(t.note)]")")
                }
            }
        }

        let testedCount = sandboxRows.filter(\.tested).count
        let execRate = allExecutable.isEmpty ? 0.0 : rate(allExecutable)
        let correctRate: Double? = allCorrect.isEmpty ? nil : rate(allCorrect.map { $0 })

        let report = SandboxReport(
            scoreTimestamp: ISO8601DateFormatter().string(from: Date()),
            rawInput: URL(fileURLWithPath: input).lastPathComponent,
            totalRows: rawResults.count,
            testedRows: testedCount,
            executableRate: execRate,
            correctRate: correctRate,
            rows: sandboxRows
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)

        if let reportPath = self.report {
            try data.write(to: URL(fileURLWithPath: reportPath))
            stderr("Wrote sandbox report to \(reportPath)")
        } else {
            print(String(decoding: data, as: UTF8.self))
        }

        printRollup(report)
    }

    // MARK: - Row scoring

    private func scoreRow(_ row: RawRowResult) async -> SandboxRowResult {
        guard let testCase = SandboxRegistry.testCase(for: row.id) else {
            return SandboxRowResult(id: row.id, tested: false, trials: [],
                                   executableRate: 0, correctRate: nil)
        }

        var trialScores: [SandboxTrialScore] = []

        for trial in row.trials {
            // Pick the first suggestion from this trial.
            guard let suggestion = trial.suggestions?.first else {
                trialScores.append(SandboxTrialScore(
                    seed: trial.seed, command: "",
                    executable: false, correct: nil, executionMs: 0,
                    note: trial.error ?? "no suggestions returned"
                ))
                continue
            }

            let rawCommand = suggestion.command
            let command = testCase.prepareCommand(rawCommand)

            let sandboxScore = await runInSandbox(command: command, testCase: testCase)

            trialScores.append(SandboxTrialScore(
                seed: trial.seed,
                command: command,
                executable: sandboxScore.executable,
                correct: sandboxScore.correct,
                executionMs: sandboxScore.executionMs,
                note: sandboxScore.note
            ))
        }

        let execRate = trialScores.isEmpty ? 0.0 : rate(trialScores.map(\.executable))
        let correctValues = trialScores.compactMap(\.correct)
        let correctRate: Double? = correctValues.isEmpty ? nil : rate(correctValues.map { $0 })

        return SandboxRowResult(
            id: row.id,
            tested: true,
            trials: trialScores,
            executableRate: execRate,
            correctRate: correctRate
        )
    }

    // MARK: - Sandbox execution

    private func runInSandbox(
        command: String,
        testCase: any SandboxTestCase
    ) async -> SandboxScore {
        // Each trial gets its own isolated temp directory.
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "shguide-sandbox-\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return SandboxScore(executable: false, correct: nil, executionMs: 0,
                                note: "failed to create temp dir: \(error)")
        }

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        do {
            try testCase.setup(in: tempDir)
        } catch {
            return SandboxScore(executable: false, correct: nil, executionMs: 0,
                                note: "fixture setup failed: \(error)")
        }

        let result = await CommandRunner.runAsync(
            command,
            in: tempDir,
            networkPolicy: testCase.networkPolicy,
            timeout: timeout
        )

        return testCase.score(command: command, result: result, in: tempDir)
    }

    // MARK: - Helpers

    private func loadRawResults(from url: URL) throws -> [RawRowResult] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        var results: [RawRowResult] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }
            guard let data = line.data(using: .utf8) else { continue }
            results.append(try decoder.decode(RawRowResult.self, from: data))
        }
        return results
    }

    private func rate(_ bools: [Bool]) -> Double {
        bools.isEmpty ? 0 : Double(bools.filter { $0 }.count) / Double(bools.count)
    }

    private func printRollup(_ r: SandboxReport) {
        let pct = { (v: Double) in String(format: "%.1f%%", v * 100) }
        let pctOpt = { (v: Double?) in v.map { String(format: "%.1f%%", $0 * 100) } ?? "  n/a" }
        stderr("""

        === sandbox-score | \(r.rawInput) | \(r.totalRows) rows total | \(r.testedRows) tested ===
          executable rate:  \(pct(r.executableRate))
          correct rate:     \(pctOpt(r.correctRate))

        """)
    }

    private func stderr(_ msg: String) {
        FileHandle.standardError.write(Data((msg + "\n").utf8))
    }
}
