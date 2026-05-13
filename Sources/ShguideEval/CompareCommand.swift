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
        let aName = a.strategy.padding(toLength: 22, withPad: " ", startingAt: 0)
        let bName = b.strategy.padding(toLength: 22, withPad: " ", startingAt: 0)
        print("metric               \(aName) \(bName)  Δ")
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
        let deltaStr = String(format: "%+.2f", delta) + unit
        print("\(label.padding(toLength: 20, withPad: " ", startingAt: 0)) \(fmt(x).padding(toLength: 22, withPad: " ", startingAt: 0)) \(fmt(y).padding(toLength: 22, withPad: " ", startingAt: 0))  \(deltaStr)")
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
