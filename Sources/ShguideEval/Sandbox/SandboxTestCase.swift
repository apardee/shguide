import Foundation

// MARK: - Execution result

struct ExecutionResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let timedOut: Bool
    let durationMs: Int
}

// MARK: - Network policy

/// Controls what network access the sandbox allows for a given test.
enum SandboxNetworkPolicy: Sendable {
    /// Block all network activity (default for file/text-processing tests).
    case none
    /// Resolve `hosts` to IPs before entering the sandbox, then allow outbound
    /// connections to exactly those addresses. DNS (port 53) to the system
    /// resolver is also allowed so the sandboxed process can resolve names.
    case outboundToHosts([String])
}

// MARK: - Sandbox score

struct SandboxScore: Sendable, Encodable {
    /// Command ran without timeout or launcher error.
    let executable: Bool
    /// Output matched expected results. nil when output validation is not
    /// applicable (e.g. side-effect-only commands).
    let correct: Bool?
    let executionMs: Int
    let note: String
}

// MARK: - Protocol

/// Each sandbox test case owns a set of eval row IDs, establishes a fixture
/// environment, runs the model-generated command inside a Seatbelt sandbox,
/// and scores the result.
protocol SandboxTestCase: Sendable {
    /// Eval row IDs this test applies to.
    var rowIDs: [String] { get }

    /// Network access the sandboxed process is allowed. Defaults to `.none`.
    var networkPolicy: SandboxNetworkPolicy { get }

    /// Populates `dir` with fixture files and directories before the command runs.
    func setup(in dir: URL) throws

    /// Optionally rewrites the model-generated command before it is executed.
    /// Use for tests that need to redirect hostnames to safe loopback addresses
    /// or clamp unbounded flags (e.g. ping count). The rewritten command is
    /// what `score` receives.
    func prepareCommand(_ command: String) -> String

    /// Produces a score from the (possibly rewritten) command string and its
    /// execution result.
    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore
}

extension SandboxTestCase {
    var networkPolicy: SandboxNetworkPolicy { .none }
    func prepareCommand(_ command: String) -> String { command }
}

// MARK: - Report types

struct SandboxTrialScore: Encodable, Sendable {
    let seed: Int
    let command: String
    let executable: Bool
    let correct: Bool?
    let executionMs: Int
    let note: String
}

struct SandboxRowResult: Encodable, Sendable {
    let id: String
    let tested: Bool
    let trials: [SandboxTrialScore]
    let executableRate: Double
    let correctRate: Double?
}

struct SandboxReport: Encodable, Sendable {
    let scoreTimestamp: String
    let rawInput: String
    let totalRows: Int
    let testedRows: Int
    let executableRate: Double
    let correctRate: Double?
    let rows: [SandboxRowResult]
}
