import Foundation
import FoundationModels

@available(macOS 26.0, *)
public struct FoundationModelsEngine: QueryEngine {
    public let useTools: Bool
    public let history: [String]
    public let temperature: Double
    public let promptVariant: PromptVariant

    public init(useTools: Bool = true, history: [String] = [], temperature: Double = 0.2, promptVariant: PromptVariant = .composition) {
        self.useTools = useTools
        self.history = history
        self.temperature = temperature
        self.promptVariant = promptVariant
    }

    public static func ensureAvailable() throws {
        switch SystemLanguageModel.default.availability {
        case .available:
            return
        case .unavailable(let reason):
            throw EngineError.modelUnavailable(reason: Self.describe(reason))
        }
    }

    static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "this device is not eligible for Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled. Turn it on in System Settings > Apple Intelligence."
        case .modelNotReady:
            return "the on-device model is still downloading or warming up. Try again in a minute."
        @unknown default:
            return "model unavailable (unknown reason)."
        }
    }

    public func forward(goal: String, context: InvocationContext) async throws -> [AnnotatedSuggestion] {
        try Self.ensureAvailable()
        let tools = buildTools(context: context)
        let instructions = Prompts.forwardInstructions(context: context, variant: promptVariant)
        let prompt = Prompts.forwardPrompt(goal: goal, context: context)
        let session = LanguageModelSession(tools: tools, instructions: instructions)

        let result: LanguageModelSession.Response<SuggestionList>
        do {
            result = try await session.respond(
                to: prompt,
                generating: SuggestionList.self,
                options: GenerationOptions(temperature: temperature, maximumResponseTokens: 600)
            )
        } catch {
            throw EngineError.generationFailed(underlying: error)
        }
        return CommandValidator.process(result.content.suggestions, context: context)
    }

    public func describe(command: String, context: InvocationContext) async throws -> ForwardExplanation {
        try Self.ensureAvailable()
        let tools = buildTools(context: context)
        let instructions = Prompts.describeInstructions(context: context)
        let prompt = Prompts.describePrompt(command: command)
        let session = LanguageModelSession(tools: tools, instructions: instructions)

        let result: LanguageModelSession.Response<Explanation>
        do {
            result = try await session.respond(
                to: prompt,
                generating: Explanation.self,
                options: GenerationOptions(temperature: temperature, maximumResponseTokens: 900)
            )
        } catch {
            throw EngineError.generationFailed(underlying: error)
        }
        let exp = result.content
        // Trust our own destructive check over the model's claim.
        let containsDestructive = exp.containsDestructive || DestructivePolicy.isDestructive(command)
        return ForwardExplanation(
            summary: exp.summary,
            parts: exp.parts.map { (token: $0.token, explanation: $0.explanation) },
            containsDestructive: containsDestructive
        )
    }

    private func buildTools(context: InvocationContext) -> [any Tool] {
        guard useTools else { return [] }
        var tools: [any Tool] = [
            CheckCommandTool(availableBinaries: context.pathBinaries),
            ManPageTool(availableBinaries: context.pathBinaries),
        ]
        if !history.isEmpty {
            tools.append(HistoryLookupTool(history: history))
        }
        return tools
    }
}
