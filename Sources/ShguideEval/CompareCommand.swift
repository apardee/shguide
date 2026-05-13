import ArgumentParser
import Foundation

@available(macOS 26.0, *)
struct CompareCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compare",
        abstract: "Diff two eval reports side by side."
    )

    @Argument(help: "Baseline report JSON.")
    var baseline: String

    @Argument(help: "Candidate report JSON.")
    var candidate: String

    func run() async throws {
        let a = try load(URL(fileURLWithPath: baseline))
        let b = try load(URL(fileURLWithPath: candidate))
        let aLabel = label(a)
        let bLabel = label(b)
        let aCol = aLabel.padding(toLength: 26, withPad: " ", startingAt: 0)
        let bCol = bLabel.padding(toLength: 26, withPad: " ", startingAt: 0)
        print("metric               \(aCol) \(bCol)  Δ")
        print("------------------------------------------------------------------------------------")
        line("coverage", a.forwardCoverageRate, b.forwardCoverageRate)
        line("coverage strict", a.forwardCoverageStrictRate ?? a.forwardCoverageRate,
                                  b.forwardCoverageStrictRate ?? b.forwardCoverageRate)
        line("validity", a.forwardValidityRate, b.forwardValidityRate)
        line("safety  ", a.safetyRate, b.safetyRate)
        line("stability", a.stabilityRate ?? 1.0, b.stabilityRate ?? 1.0)
        line("med lat ", a.medianLatencySeconds, b.medianLatencySeconds, unit: "s")
        line("p95 lat ", a.p95LatencySeconds, b.p95LatencySeconds, unit: "s")
    }

    private func label(_ r: Report) -> String {
        let seeds = r.seeds ?? 1
        let temp = r.temperature.map { String(format: "T=%.2f", $0) } ?? "T=?"
        return "\(r.strategy) (\(seeds)×\(temp))"
    }

    private func line(_ label: String, _ x: Double, _ y: Double, unit: String = "%") {
        let scale = unit == "%" ? 100.0 : 1.0
        let delta = (y - x) * scale
        let fmt: (Double) -> String = { unit == "%" ? String(format: "%.1f%%", $0 * 100) : String(format: "%.2fs", $0) }
        let deltaStr = String(format: "%+.2f", delta) + unit
        let labelCol = label.padding(toLength: 20, withPad: " ", startingAt: 0)
        let xCol = fmt(x).padding(toLength: 26, withPad: " ", startingAt: 0)
        let yCol = fmt(y).padding(toLength: 26, withPad: " ", startingAt: 0)
        print("\(labelCol) \(xCol) \(yCol)  \(deltaStr)")
    }

    private func load(_ url: URL) throws -> Report {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Report.self, from: data)
    }

    struct Report: Decodable {
        let strategy: String
        let seeds: Int?
        let temperature: Double?
        let forwardCoverageRate: Double
        let forwardCoverageStrictRate: Double?
        let forwardValidityRate: Double
        let safetyRate: Double
        let stabilityRate: Double?
        let medianLatencySeconds: Double
        let p95LatencySeconds: Double
    }
}
