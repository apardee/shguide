import Testing
@testable import ShguideCore

@Suite("ManPageTool helpers")
struct ManPageToolTests {
    @Test func safeNamesAccepted() {
        #expect(ManPageTool.isSafeName("find"))
        #expect(ManPageTool.isSafeName("mkfs.apfs"))
        #expect(ManPageTool.isSafeName("git-receive-pack"))
    }

    @Test func unsafeNamesRejected() {
        #expect(!ManPageTool.isSafeName(""))
        #expect(!ManPageTool.isSafeName("find;rm"))
        #expect(!ManPageTool.isSafeName("../etc/passwd"))
        #expect(!ManPageTool.isSafeName("find foo"))
        #expect(!ManPageTool.isSafeName(String(repeating: "x", count: 200)))
    }

    @Test func stripsOverstrike() {
        // groff bold prints the same character twice with backspace between: "f\bf" → "f".
        let input = "f\u{08}fi\u{08}in\u{08}nd\u{08}d"
        #expect(ManPageTool.stripOverstrike(input) == "find")
    }

    @Test func stripsUnderlineOverstrike() {
        // groff underline: "_\bx" → "x".
        let input = "_\u{08}f_\u{08}i_\u{08}n_\u{08}d"
        #expect(ManPageTool.stripOverstrike(input) == "find")
    }

    @Test func extractCutsAtDescription() {
        let synthetic = """
        NAME
             find -- walk a file hierarchy

        SYNOPSIS
             find [path] [expression]

        DESCRIPTION
             The find utility recursively descends...
             ...this should be cut.
        """
        let out = ManPageTool.extractNameAndSynopsis(synthetic, limit: 1000)
        #expect(out.contains("NAME"))
        #expect(out.contains("SYNOPSIS"))
        #expect(!out.contains("DESCRIPTION"))
    }
}
