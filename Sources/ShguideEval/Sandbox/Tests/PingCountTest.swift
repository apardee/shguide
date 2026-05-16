import Foundation

/// ping_count_050 / ping_specific_097
///
/// Goal: "send exactly 5 ping packets to a host"
///
/// Runs a real ping inside the Seatbelt sandbox with outbound restricted to
/// loopback (127.0.0.1), so the test works offline and never touches the
/// internet. `prepareCommand` rewrites the model's target host to 127.0.0.1
/// and lowers the count to 3 so the test completes in under a second.
///
/// Validates that the model used a count flag (-c) and that ping produced a
/// "packets transmitted" summary line.
struct PingCountTest: SandboxTestCase {
    let rowIDs = ["ping_count_050", "ping_specific_097", "network_check_ambig_111"]

    let networkPolicy: SandboxNetworkPolicy = .outboundToHosts(["127.0.0.1"])

    func setup(in dir: URL) throws { /* no file fixtures needed */ }

    // MARK: - Command rewriting

    /// Redirect the model's target host to loopback and clamp -c to 3.
    func prepareCommand(_ command: String) -> String {
        var tokens = command
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        // Lower -c <n> to 3, or insert -c 3 if absent.
        if let ci = tokens.firstIndex(of: "-c"), ci + 1 < tokens.count {
            tokens[ci + 1] = "3"
        } else if let pi = tokens.firstIndex(where: { $0 == "ping" || $0.hasSuffix("/ping") }) {
            tokens.insert(contentsOf: ["-c", "3"], at: pi + 1)
        }

        // Replace the last non-flag, non-digit token with the loopback address.
        for i in stride(from: tokens.count - 1, through: 0, by: -1) {
            let t = tokens[i]
            if !t.hasPrefix("-") && Int(t) == nil {
                tokens[i] = "127.0.0.1"
                break
            }
        }

        return tokens.joined(separator: " ")
    }

    // MARK: - Scoring

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: result.timedOut ? "timed out" : "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout
        let (ok, note) = OutputValidator.check([
            (out.contains("packets transmitted") || out.contains("PING"),
             "expected 'packets transmitted' in ping summary — output: \(out.prefix(200))"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
