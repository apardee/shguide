import FoundationModels

@available(macOS 26.0, *)
@Generable
public struct Suggestion: Equatable, Sendable {
    @Guide(description: "A single complete shell command. No markdown, no leading $ or >, no surrounding quotes.")
    public var command: String

    @Guide(description: "One-sentence explanation of what running this command does on macOS.")
    public var explanation: String

    @Guide(
        description: "safe = no side effects beyond stdout. caution = writes to user files but reversible. destructive = deletes data, modifies system state, or is hard to undo.",
        .anyOf(["safe", "caution", "destructive"])
    )
    public var risk: String

    public init(command: String, explanation: String, risk: String) {
        self.command = command
        self.explanation = explanation
        self.risk = risk
    }
}

@available(macOS 26.0, *)
@Generable
public struct SuggestionList: Sendable {
    @Guide(
        description: "Between 1 and 4 candidate commands ordered by relevance.",
        .count(1...4)
    )
    public var suggestions: [Suggestion]

    public init(suggestions: [Suggestion]) {
        self.suggestions = suggestions
    }
}

@available(macOS 26.0, *)
@Generable
public struct ExplanationPart: Sendable {
    @Guide(description: "The exact substring or pipe stage being explained, copied verbatim from the input command.")
    public var token: String

    @Guide(description: "Plain-English description of what this segment does, including flag meanings.")
    public var explanation: String

    public init(token: String, explanation: String) {
        self.token = token
        self.explanation = explanation
    }
}

@available(macOS 26.0, *)
@Generable
public struct Explanation: Sendable {
    @Guide(description: "One or two sentences summarising the overall pipeline.")
    public var summary: String

    @Guide(
        description: "Ordered breakdown, one entry per pipe stage or major token group.",
        .count(1...20)
    )
    public var parts: [ExplanationPart]

    @Guide(description: "True if any segment deletes data, modifies system state, or is hard to reverse.")
    public var containsDestructive: Bool

    public init(summary: String, parts: [ExplanationPart], containsDestructive: Bool) {
        self.summary = summary
        self.parts = parts
        self.containsDestructive = containsDestructive
    }
}

public enum Risk: String, Sendable, CaseIterable {
    case safe
    case caution
    case destructive

    public init(modelLabel: String) {
        switch modelLabel.lowercased() {
        case "destructive": self = .destructive
        case "caution": self = .caution
        default: self = .safe
        }
    }
}

public struct AnnotatedSuggestion: Sendable, Equatable {
    public var command: String
    public var explanation: String
    public var risk: Risk
    public var fromHistory: Bool

    public init(command: String, explanation: String, risk: Risk, fromHistory: Bool) {
        self.command = command
        self.explanation = explanation
        self.risk = risk
        self.fromHistory = fromHistory
    }
}
