import ArgumentParser
import Foundation
import ShguideCore

/// Bounded concurrency semaphore using a Swift actor.
private actor Semaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(count: Int) { self.count = count }

    func wait() async {
        if count > 0 {
            count -= 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func signal() {
        if let first = waiters.first {
            waiters.removeFirst()
            first.resume()
        } else {
            count += 1
        }
    }
}

@available(macOS 26.0, *)
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run eval prompts through a model and emit raw JSONL output."
    )

    @Option(name: .customLong("dataset"), help: "Path to the JSONL dataset.")
    var dataset: String

    @Option(name: .customLong("model"), help: "Model backend: foundation-models, foundation-models+tools, mock.")
    var model: String = "foundation-models"

    @Option(name: .customLong("output"), help: "Path to write raw JSONL output.")
    var output: String

    @Option(name: .customLong("concurrency"), help: "Max concurrent requests (default 4).")
    var concurrency: Int = 4

    @Option(name: .customLong("seeds"), help: "Independent trials per row (>= 1).")
    var seeds: Int = 1

    @Option(name: .customLong("temperature"), help: "Sampling temperature.")
    var temperature: Double = 0.2

    @Option(name: .customLong("only-ids"), help: "Comma-separated row ids to run exclusively.")
    var onlyIds: String?

    @Option(name: .customLong("limit"), help: "Optional cap on number of rows to run.")
    var limit: Int?

    func run() async throws {
        guard seeds >= 1 else { throw ValidationError("--seeds must be >= 1") }
        guard concurrency >= 1 else { throw ValidationError("--concurrency must be >= 1") }

        let url = URL(fileURLWithPath: dataset)
        let (rows, benchmarkVersion) = try Dataset.loadWithVersion(from: url)
        var filtered = rows
        if let onlyIds {
            let idSet = Set(onlyIds.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            filtered = rows.filter { idSet.contains($0.id) }
            guard !filtered.isEmpty else { throw ValidationError("--only-ids matched no rows") }
        }
        let chosen = limit.map { Array(filtered.prefix($0)) } ?? filtered

        let pathBinaries = PathInventory.snapshot()
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let runTimestamp = ISO8601DateFormatter().string(from: Date())

        stderr("Running \(chosen.count) rows × \(seeds) seeds  model=\(model)  concurrency=\(concurrency)")

        let sem = Semaphore(count: concurrency)
        var indexedResults: [(Int, RawRowResult)] = []
        let lock = NSLock()

        await withTaskGroup(of: (Int, RawRowResult).self) { group in
            for (idx, row) in chosen.enumerated() {
                group.addTask {
                    await sem.wait()
                    defer { Task { await sem.signal() } }
                    let result = await self.runRow(
                        idx: idx, total: chosen.count,
                        row: row, pathBinaries: pathBinaries,
                        osVersion: osVersion, runTimestamp: runTimestamp,
                        benchmarkVersion: benchmarkVersion
                    )
                    return (idx, result)
                }
            }
            for await pair in group {
                lock.withLock { indexedResults.append(pair) }
            }
        }

        indexedResults.sort { $0.0 < $1.0 }
        let rawResults = indexedResults.map(\.1)

        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        var lines: [String] = []
        for r in rawResults {
            let data = try encoder.encode(r)
            lines.append(String(decoding: data, as: UTF8.self))
        }
        try (lines.joined(separator: "\n") + "\n").write(toFile: output, atomically: true, encoding: .utf8)
        stderr("Wrote \(rawResults.count) rows to \(output)")
    }

    // MARK: - Row execution

    private func runRow(
        idx: Int, total: Int,
        row: EvalRow,
        pathBinaries: Set<String>,
        osVersion: String,
        runTimestamp: String,
        benchmarkVersion: Int
    ) async -> RawRowResult {
        let context = InvocationContext(
            shellName: "zsh",
            osVersion: osVersion,
            pathBinaries: pathBinaries,
            historyMatches: [],
            includeDestructive: false,
            useTools: model == "foundation-models+tools"
        )

        var trials: [RawTrial] = []
        for seed in 0..<seeds {
            let started = Date()
            do {
                trials.append(try await runTrialWithRetry(row: row, context: context, seed: seed))
            } catch {
                trials.append(RawTrial(
                    seed: seed, suggestions: nil, explanation: nil,
                    latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                    error: String(describing: error)
                ))
            }
        }

        let glyphs = trials.map { t -> String in
            guard t.error == nil else { return "E" }
            return (!(t.suggestions ?? []).isEmpty || t.explanation != nil) ? "✓" : "✗"
        }.joined()
        stderr("[\(idx + 1)/\(total)] \(row.id)  \(glyphs)")

        return RawRowResult(
            id: row.id, mode: row.mode, goal: row.goal, command: row.command,
            model: model, temperature: temperature,
            benchmarkVersion: benchmarkVersion, runTimestamp: runTimestamp,
            trials: trials
        )
    }

    // MARK: - Trial execution

    private func runTrialWithRetry(row: EvalRow, context: InvocationContext, seed: Int) async throws -> RawTrial {
        let backoffs: [UInt64] = [500_000_000, 1_500_000_000, 4_000_000_000]
        var lastError: Error?
        for attempt in 0...backoffs.count {
            do {
                return try await runTrial(row: row, context: context, seed: seed)
            } catch {
                lastError = error
                if !isTransient(error) || attempt == backoffs.count { throw error }
                try? await Task.sleep(nanoseconds: backoffs[attempt])
            }
        }
        throw lastError!
    }

    private func isTransient(_ error: Error) -> Bool {
        let s = String(describing: error)
        return s.contains("ModelManagerError Code=1013") || s.contains("ModelManagerError Code=1014")
    }

    private func runTrial(row: EvalRow, context: InvocationContext, seed: Int) async throws -> RawTrial {
        let started = Date()
        let engine = makeEngine()

        switch row.mode {
        case "forward":
            guard let goal = row.goal else { throw RunError.malformedRow(row.id) }
            let suggestions = try await engine.forward(goal: goal, context: context)
            let raw = suggestions.map { RawSuggestion(command: $0.command, explanation: $0.explanation) }
            return RawTrial(seed: seed, suggestions: raw, explanation: nil,
                            latencyMs: Int(Date().timeIntervalSince(started) * 1000), error: nil)

        case "describe":
            guard let cmd = row.command else { throw RunError.malformedRow(row.id) }
            let exp = try await engine.describe(command: cmd, context: context)
            let rawExp = RawExplanation(
                summary: exp.summary,
                parts: exp.parts.map { RawExplanationPart(token: $0.token, explanation: $0.explanation) }
            )
            return RawTrial(seed: seed, suggestions: nil, explanation: rawExp,
                            latencyMs: Int(Date().timeIntervalSince(started) * 1000), error: nil)

        default:
            throw RunError.malformedRow(row.id)
        }
    }

    private func makeEngine() -> any QueryEngine {
        switch model {
        case "mock":                    return MockEngine()
        case "foundation-models+tools": return FoundationModelsEngine(useTools: true, temperature: temperature)
        default:                        return FoundationModelsEngine(useTools: false, temperature: temperature)
        }
    }

    private func stderr(_ msg: String) {
        FileHandle.standardError.write(Data((msg + "\n").utf8))
    }

    enum RunError: Error, CustomStringConvertible {
        case malformedRow(String)
        var description: String {
            switch self { case .malformedRow(let id): return "malformed row: \(id)" }
        }
    }
}
