import Testing
@testable import ShguideCore

@Suite("ShellHistory")
struct ShellHistoryTests {
    @Test func parsesZshExtendedLine() {
        let parsed = ShellHistory.parseLine(": 1700000000:0;ls -la")
        #expect(parsed == "ls -la")
    }

    @Test func parsesPlainBashLine() {
        let parsed = ShellHistory.parseLine("git status")
        #expect(parsed == "git status")
    }

    @Test func ignoresEmptyAndMalformed() {
        #expect(ShellHistory.parseLine("") == nil)
        #expect(ShellHistory.parseLine(": 17:0") == nil) // no semicolon, malformed
    }

    @Test func filtersSecrets() {
        #expect(ShellHistory.isLikelySecret("export AWS_SECRET_ACCESS_KEY=abc"))
        #expect(ShellHistory.isLikelySecret("openssl rsa -in -----BEGIN RSA PRIVATE KEY-----"))
        #expect(!ShellHistory.isLikelySecret("export PATH=/opt/bin:$PATH"))
        #expect(!ShellHistory.isLikelySecret("git push origin main"))
    }

    @Test func matchScoresByKeywordOverlap() {
        let history = [
            "find . -type f -size +500M",
            "du -sh *",
            "git status",
            "find . -name '*.swift'",
        ]
        let results = ShellHistory.match(keywords: ["find", "size"], in: history, limit: 5)
        #expect(results.count == 2)
        #expect(results.first?.command == "find . -type f -size +500M") // matches both keywords -> higher score
    }
}
