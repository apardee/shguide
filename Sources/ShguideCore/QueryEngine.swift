public struct HistoryEntry: Sendable, Equatable {
    public let command: String
    public let occurrences: Int

    public init(command: String, occurrences: Int) {
        self.command = command
        self.occurrences = occurrences
    }
}

public struct InvocationContext: Sendable {
    public let shellName: String
    public let osVersion: String
    public let pathBinaries: Set<String>
    public let historyMatches: [HistoryEntry]
    public let includeDestructive: Bool
    public let useTools: Bool

    public init(
        shellName: String,
        osVersion: String,
        pathBinaries: Set<String>,
        historyMatches: [HistoryEntry] = [],
        includeDestructive: Bool = false,
        useTools: Bool = true
    ) {
        self.shellName = shellName
        self.osVersion = osVersion
        self.pathBinaries = pathBinaries
        self.historyMatches = historyMatches
        self.includeDestructive = includeDestructive
        self.useTools = useTools
    }
}

public struct ForwardExplanation: Sendable {
    public let summary: String
    public let parts: [(token: String, explanation: String)]
    public let containsDestructive: Bool

    public init(summary: String, parts: [(token: String, explanation: String)], containsDestructive: Bool) {
        self.summary = summary
        self.parts = parts
        self.containsDestructive = containsDestructive
    }
}

public protocol QueryEngine: Sendable {
    func forward(goal: String, context: InvocationContext) async throws -> [AnnotatedSuggestion]
    func describe(command: String, context: InvocationContext) async throws -> ForwardExplanation
}

public enum EngineError: Error, CustomStringConvertible {
    case modelUnavailable(reason: String)
    case generationFailed(underlying: Error)
    case emptyResponse

    public var description: String {
        switch self {
        case .modelUnavailable(let reason): return "Foundation Models unavailable: \(reason)"
        case .generationFailed(let err): return "Generation failed: \(err)"
        case .emptyResponse: return "Model returned an empty response."
        }
    }
}
