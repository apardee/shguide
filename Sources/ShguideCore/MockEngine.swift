public struct MockEngine: QueryEngine {
    public init() {}

    public func forward(goal: String, context: InvocationContext) async throws -> [AnnotatedSuggestion] {
        let lowered = goal.lowercased()
        let candidates: [AnnotatedSuggestion]

        if lowered.contains("large") && (lowered.contains("file") || lowered.contains("size")) {
            candidates = [
                AnnotatedSuggestion(
                    command: "find . -type f -size +500M",
                    explanation: "List files in the current directory tree larger than 500 megabytes.",
                    risk: .safe,
                    fromHistory: false
                ),
                AnnotatedSuggestion(
                    command: "find . -type f -size +100M -exec du -h {} + | sort -hr",
                    explanation: "Find files larger than 100MB and print them in human-readable size sorted from biggest to smallest.",
                    risk: .safe,
                    fromHistory: false
                ),
            ]
        } else if lowered.contains("delete") || lowered.contains("remove") {
            candidates = [
                AnnotatedSuggestion(
                    command: "rm -rf ./tmp",
                    explanation: "Recursively delete the ./tmp directory without prompting.",
                    risk: .destructive,
                    fromHistory: false
                )
            ]
        } else {
            candidates = [
                AnnotatedSuggestion(
                    command: "echo '\(goal)'",
                    explanation: "Echo the goal back. (Mock engine fallback — wire FoundationModelsEngine for real suggestions.)",
                    risk: .safe,
                    fromHistory: false
                )
            ]
        }

        return candidates.filter { context.includeDestructive || $0.risk != .destructive }
    }

    public func describe(command: String, context: InvocationContext) async throws -> ForwardExplanation {
        ForwardExplanation(
            summary: "Mock description of `\(command)`.",
            parts: [(token: command, explanation: "The mock engine does not analyse pipelines. Wire FoundationModelsEngine for real analysis.")],
            containsDestructive: false
        )
    }
}
