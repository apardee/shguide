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
        print(String(format: "metric              %-22s %-22s  Δ", a.strategy, b.strategy))
        print("--------------------------------------------------------------------------")
        line("coverage", a.forwardCoverageRate, b.forwardCoverageRate)
        line("validity", a.forwardValidityRate, b.forwardValidityRate)
        line("safety  ", a.safetyRate, b.safetyRate)
        line("med lat ", a.medianLatencySeconds, b.medianLatencySeconds, unit: "s")
        line("p95 lat ", a.p95LatencySeconds, b.p95LatencySeconds, unit: "s")
    }

    private func line(_ label: String, _ x: Double, _ y: Double, unit: String = "%") {
        let scale = unit == "%" ? 100.0 : 1.0
        let delta = (y - x) * scale
        let fmt: (Double) -> String = { unit == "%" ? String(format: "%.1f%%", $0 * 100) : String(format: "%.2fs", $0) }
        print(String(format: "%-20s %-22s %-22s  %+.2f%@", label, fmt(x), fmt(y), delta, unit))
    }

    private func load(_ url: URL) throws -> Report {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Report.self, from: data)
    }

    struct Report: Decodable {
        let strategy: String
        let forwardCoverageRate: Double
        let forwardValidityRate: Double
        let safetyRate: Double
        let medianLatencySeconds: Double
        let p95LatencySeconds: Double
    }
}
