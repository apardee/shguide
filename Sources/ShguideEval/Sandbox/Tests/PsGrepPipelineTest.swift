import Foundation

/// ps_aux_055 / pgrep_name_054 / process_kill_ambig_110
///
/// NOTE: `ps` and `top` require com.apple.system-task-ports.read — a private
/// entitlement that Seatbelt cannot grant. Both commands fail with
/// "Operation not permitted" inside the sandbox regardless of network or
/// process-info policy. Scoring is therefore done by string inspection,
/// verifying that the model produced a structurally correct command.
///
/// ps_aux_055: "show all running processes with full detail"
///   Expects: ps aux  (binary=ps, flags include a and u or just aux/axu)
///
/// pgrep_name_054: "find the pid of a running process by name"
///   Expects: pgrep <name>  OR  ps aux | grep <name>
///   The grep-based pipeline must have the pipe joining ps and grep.
struct PsGrepPipelineTest: SandboxTestCase {
    let rowIDs = ["ps_aux_055", "pgrep_name_054", "process_kill_ambig_110"]

    func setup(in dir: URL) throws { /* no fixtures needed */ }

    func prepareCommand(_ command: String) -> String { command }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let tokens = command
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        let hasPsOrPgrep = tokens.contains(where: {
            $0 == "ps" || $0.hasSuffix("/ps") || $0 == "pgrep" || $0.hasSuffix("/pgrep")
        })
        let isPipeline  = command.contains("|")
        let hasGrepInPipe = isPipeline && command.contains("grep")

        // ps_aux_055 variants: ps aux, ps -aux, ps axu, ps -ef, top
        let isDetailedPs = command.contains("ps") && (
            command.contains("aux") || command.contains("axu") ||
            command.contains("-ef") || command.contains("-e")
        )
        // top as alternative is accepted structurally
        let hasTop = tokens.contains(where: { $0 == "top" || $0.hasSuffix("/top") })

        // pgrep pipeline: ps aux | grep <name>  OR  pgrep <name>
        let isPgrepCmd     = tokens.contains(where: { $0 == "pgrep" || $0.hasSuffix("/pgrep") })
        let isPsGrepPipe   = command.contains("ps") && hasGrepInPipe

        let isForAux     = command.contains("ps_aux") || isDetailedPs || hasTop
        let isForPgrep   = isPgrepCmd || isPsGrepPipe

        let (ok, note): (Bool, String)
        if isForAux && !isForPgrep {
            (ok, note) = OutputValidator.check([
                (isDetailedPs || hasTop, "command does not use ps with detail flags (aux/-ef) or top"),
            ])
        } else {
            (ok, note) = OutputValidator.check([
                (hasPsOrPgrep || isPsGrepPipe,
                 "command does not use ps, pgrep, or a ps|grep pipeline"),
            ])
        }
        return SandboxScore(
            executable: true,
            correct: ok,
            executionMs: 0,
            note: ok ? "(string-verified — ps requires system-task-ports.read, not grantable by Seatbelt)" : note
        )
    }
}
