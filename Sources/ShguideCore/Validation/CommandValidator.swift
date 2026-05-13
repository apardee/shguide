import Foundation

public enum CommandValidator {
    /// Extracts the leading binary name of each pipeline segment.
    public static func leadingBinaries(in command: String) -> [String] {
        let separators = CharacterSet(charactersIn: "|;&")
        var result: [String] = []
        for raw in command.components(separatedBy: separators) {
            let seg = raw.trimmingCharacters(in: .whitespaces)
            guard !seg.isEmpty else { continue }
            // Skip variable assignments like FOO=bar prefixed to a command.
            let tokens = seg.split(whereSeparator: { $0.isWhitespace })
            var firstNonAssignment: String?
            for token in tokens {
                if token.contains("=") && firstNonAssignment == nil {
                    continue
                }
                firstNonAssignment = String(token)
                break
            }
            if let bin = firstNonAssignment {
                result.append(bin)
            }
        }
        return result
    }

    /// Returns true if every leading binary is present in pathBinaries OR is a shell builtin.
    public static func looksRunnable(command: String, pathBinaries: Set<String>) -> Bool {
        for bin in leadingBinaries(in: command) {
            if shellBuiltins.contains(bin) { continue }
            if pathBinaries.contains(bin) { continue }
            return false
        }
        return true
    }

    /// Common zsh/bash builtins we should not reject just because they are not on $PATH.
    static let shellBuiltins: Set<String> = [
        "cd", "echo", "export", "alias", "unalias", "set", "unset", "source", ".",
        "exec", "exit", "return", "shift", "read", "test", "type", "command",
        "true", "false", "pwd", "umask", "wait", "jobs", "fg", "bg", "trap",
        "let", "declare", "typeset", "history", "printf",
    ]

    /// Apply post-generation processing to model suggestions:
    /// - drop syntactically empty rows,
    /// - drop rows whose binaries are missing from this system,
    /// - re-classify risk through DestructivePolicy,
    /// - apply includeDestructive filter,
    /// - tag suggestions whose command matches the user's history.
    public static func process(
        _ suggestions: [Suggestion],
        context: InvocationContext
    ) -> [AnnotatedSuggestion] {
        let historySet = Set(context.historyMatches.map(\.command))
        var out: [AnnotatedSuggestion] = []
        for s in suggestions {
            let cmd = s.command.trimmingCharacters(in: .whitespaces)
            guard !cmd.isEmpty else { continue }
            if !looksRunnable(command: cmd, pathBinaries: context.pathBinaries) { continue }
            let risk = DestructivePolicy.effectiveRisk(command: cmd, modelLabel: s.risk)
            if risk == .destructive && !context.includeDestructive { continue }
            let fromHistory = historySet.contains(cmd)
            out.append(AnnotatedSuggestion(
                command: cmd,
                explanation: s.explanation,
                risk: risk,
                fromHistory: fromHistory
            ))
        }
        return out
    }
}
