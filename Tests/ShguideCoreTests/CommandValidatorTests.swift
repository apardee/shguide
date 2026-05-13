import Testing
@testable import ShguideCore

@Suite("CommandValidator")
struct CommandValidatorTests {
    @Test func leadingBinariesSimple() {
        #expect(CommandValidator.leadingBinaries(in: "find . -type f") == ["find"])
    }

    @Test func leadingBinariesPipeline() {
        let cmd = "grep -r ERROR /var/log/nginx | cut -d ' ' -f 5 | sort | uniq -c"
        #expect(CommandValidator.leadingBinaries(in: cmd) == ["grep", "cut", "sort", "uniq"])
    }

    @Test func leadingBinariesSkipsAssignment() {
        #expect(CommandValidator.leadingBinaries(in: "FOO=bar make build") == ["make"])
    }

    @Test func builtinsAreRunnable() {
        #expect(CommandValidator.looksRunnable(command: "cd /tmp && pwd", pathBinaries: []))
    }

    @Test func runnableRequiresKnownBinary() {
        #expect(!CommandValidator.looksRunnable(command: "thisdoesnotexist --foo", pathBinaries: []))
        #expect(CommandValidator.looksRunnable(command: "find .", pathBinaries: ["find"]))
    }

    @Test func processDropsUnknownBinary() {
        let ctx = InvocationContext(
            shellName: "zsh",
            osVersion: "26.0",
            pathBinaries: ["find"],
            includeDestructive: false
        )
        let raw = [
            Suggestion(command: "find . -type f", explanation: "ok", risk: "safe"),
            Suggestion(command: "totally-fake-tool --do", explanation: "should be dropped", risk: "safe"),
        ]
        let out = CommandValidator.process(raw, context: ctx)
        #expect(out.count == 1)
        #expect(out.first?.command == "find . -type f")
    }

    @Test func processFiltersDestructiveByDefault() {
        let ctx = InvocationContext(
            shellName: "zsh",
            osVersion: "26.0",
            pathBinaries: ["rm", "ls"],
            includeDestructive: false
        )
        let raw = [
            Suggestion(command: "rm -rf ./build", explanation: "remove", risk: "destructive"),
            Suggestion(command: "ls -la", explanation: "list", risk: "safe"),
        ]
        let out = CommandValidator.process(raw, context: ctx)
        #expect(out.count == 1)
        #expect(out.first?.command == "ls -la")
    }

    @Test func processKeepsDestructiveWhenOptedIn() {
        let ctx = InvocationContext(
            shellName: "zsh",
            osVersion: "26.0",
            pathBinaries: ["rm"],
            includeDestructive: true
        )
        let raw = [Suggestion(command: "rm -rf ./build", explanation: "remove", risk: "safe")]
        let out = CommandValidator.process(raw, context: ctx)
        #expect(out.count == 1)
        #expect(out.first?.risk == .destructive) // upgraded by policy
    }

    @Test func processTagsHistoryMatches() {
        let ctx = InvocationContext(
            shellName: "zsh",
            osVersion: "26.0",
            pathBinaries: ["find"],
            historyMatches: [HistoryEntry(command: "find . -type f", occurrences: 3)],
            includeDestructive: false
        )
        let raw = [Suggestion(command: "find . -type f", explanation: "ok", risk: "safe")]
        let out = CommandValidator.process(raw, context: ctx)
        #expect(out.first?.fromHistory == true)
    }
}
