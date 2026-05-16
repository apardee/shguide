import Foundation

/// sleep_specific_105
///
/// Goal: "pause the script for 30 seconds then echo done"
///
/// The canonical form uses the && compound operator:
///   sleep 30 && echo done
///
/// A 30-second sleep cannot run inside the sandbox (it would hit the
/// timeout and be killed). `prepareCommand` rewrites the sleep duration
/// to 0 so the compound command completes immediately, while preserving
/// the structural elements the test actually cares about:
///   • `sleep` is invoked
///   • `&&` (or `;`) chains it to a second command
///   • `echo` (or equivalent) follows
///
/// Scoring validates both command structure and actual stdout output.
struct CompoundEchoTest: SandboxTestCase {
    // sleep_seconds_071 ("wait 30 seconds") does not require a compound command —
    // that row is intentionally excluded here.
    let rowIDs = ["sleep_specific_105"]

    func setup(in dir: URL) throws { /* no fixtures needed */ }

    func prepareCommand(_ command: String) -> String {
        // Rewrite the sleep duration to 0 to prevent sandbox timeout.
        // Matches: sleep <number>  (integer or decimal, with or without units)
        guard let match = command.firstMatch(of: #/sleep\s+(\d+(?:\.\d+)?[smhd]?)/#) else {
            return command
        }
        return command.replacingCharacters(in: match.range, with: "sleep 0")
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        // Structure check: the original model command (before rewrite) should
        // contain sleep, a compound operator, and some follow-up command.
        // We receive the rewritten command here, but the && / ; structure
        // is preserved by prepareCommand.
        let hasSleep    = command.contains("sleep")
        let hasCompound = command.contains("&&") || command.contains(";")
        let hasEcho     = command.contains("echo") || command.contains("print")

        let (structOk, structNote) = OutputValidator.check([
            (hasSleep,    "command does not invoke sleep"),
            (hasCompound, "no compound operator (&& or ;) — commands not chained"),
            (hasEcho,     "no echo/print after sleep — second command missing"),
        ])
        guard structOk else {
            return SandboxScore(executable: true, correct: false,
                                executionMs: result.durationMs, note: structNote)
        }

        // Execution check: the rewritten command should have produced output.
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let (ok, note) = OutputValidator.check([
            (!result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
             "sleep 0 && echo ran but produced no output — echo may be missing or &&  broken"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
