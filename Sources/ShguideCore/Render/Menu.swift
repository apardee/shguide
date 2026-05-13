import Foundation

public enum MenuRenderer {
    public static func renderForward(suggestions: [AnnotatedSuggestion], ansi: ANSI) -> String {
        guard !suggestions.isEmpty else {
            return ansi.dim("No suggestions. Try rephrasing the goal, or pass --include-destructive if the answer requires a risky command.")
        }
        var lines: [String] = []
        for (idx, s) in suggestions.enumerated() {
            let n = ansi.bold("\(idx + 1).")
            let cmd = render(command: s.command, risk: s.risk, ansi: ansi)
            let tag = s.fromHistory ? " " + ansi.cyan("[from history]") : ""
            lines.append("\(n) \(cmd)\(tag)")
            lines.append("   " + ansi.dim(s.explanation))
        }
        return lines.joined(separator: "\n")
    }

    public static func renderDescribe(explanation: ForwardExplanation, ansi: ANSI) -> String {
        var lines: [String] = []
        if explanation.containsDestructive {
            lines.append(ansi.red("⚠ This command is destructive or hard to reverse."))
            lines.append("")
        }
        lines.append(explanation.summary)
        lines.append("")
        for (idx, part) in explanation.parts.enumerated() {
            lines.append("\(ansi.bold("\(idx + 1)."))  \(ansi.cyan(part.token))")
            lines.append("    \(part.explanation)")
        }
        return lines.joined(separator: "\n")
    }

    public static func renderJSON(suggestions: [AnnotatedSuggestion]) throws -> String {
        let payload = suggestions.map {
            [
                "command": $0.command,
                "explanation": $0.explanation,
                "risk": $0.risk.rawValue,
                "from_history": $0.fromHistory ? "true" : "false",
            ]
        }
        let data = try JSONSerialization.data(
            withJSONObject: payload.map { dict -> [String: Any] in
                var out: [String: Any] = dict
                out["from_history"] = dict["from_history"] == "true"
                return out
            },
            options: [.prettyPrinted, .sortedKeys]
        )
        return String(decoding: data, as: UTF8.self)
    }

    public static func renderDescribeJSON(_ exp: ForwardExplanation) throws -> String {
        let payload: [String: Any] = [
            "summary": exp.summary,
            "contains_destructive": exp.containsDestructive,
            "parts": exp.parts.map { ["token": $0.token, "explanation": $0.explanation] },
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func render(command: String, risk: Risk, ansi: ANSI) -> String {
        switch risk {
        case .destructive: return ansi.red(command) + " " + ansi.red("[destructive]")
        case .caution: return ansi.yellow(command)
        case .safe: return command
        }
    }
}
