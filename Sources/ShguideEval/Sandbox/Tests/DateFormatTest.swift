import Foundation

/// date_now_069 / date_format_iso_070
///
/// date_now_069: "print the current date and time"
///   Canonical: date
///   Output must be non-empty and contain the current year.
///
/// date_format_iso_070: "print today's date in YYYY-MM-DD format"
///   Canonical: date +%Y-%m-%d
///   Output must match the ISO 8601 date pattern YYYY-MM-DD.
///
/// No fixture needed. date always reads the system clock.
struct DateFormatTest: SandboxTestCase {
    let rowIDs = ["date_now_069", "date_format_iso_070"]

    func setup(in dir: URL) throws { /* no fixtures needed */ }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let wantsISO = command.contains("%Y-%m-%d") || command.contains("iso") || command.contains("ISO")
            || command.contains("date_format")

        let (ok, note): (Bool, String)
        if wantsISO {
            let hasISODate = out.contains(#/\d{4}-\d{2}-\d{2}/#)
            (ok, note) = OutputValidator.check([
                (hasISODate, "output '\(out.prefix(40))' does not match YYYY-MM-DD — missing format string or wrong flag"),
            ])
        } else {
            let currentYear = Calendar.current.component(.year, from: Date())
            let hasYear = out.contains(String(currentYear))
            (ok, note) = OutputValidator.check([
                (!out.isEmpty, "no output from date"),
                (hasYear,      "current year \(currentYear) not in output '\(out.prefix(60))'"),
            ])
        }
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
