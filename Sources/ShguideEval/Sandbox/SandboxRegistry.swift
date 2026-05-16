import Foundation

/// Central registry of all sandbox test cases.
///
/// `all` is the single source of truth. To add a new test, implement
/// `SandboxTestCase` and add an instance here.
enum SandboxRegistry {

    static let all: [any SandboxTestCase] = [
        // File discovery
        FindLargeFilesTest(),
        FindByNameTest(),
        FindEmptyTest(),
        FindRecentTest(),
        FindExtCountTest(),

        // Text search
        GrepRecursiveTest(),
        GrepIgnoreCaseTest(),

        // Text processing
        WordCountTest(),
        SortUniqCountTest(),
        AwkColumnTest(),
        HeadTailTest(),
        TrUppercaseTest(),
        SedReplaceTest(),
        DiffFilesTest(),

        // File system operations
        TouchFileTest(),
        MkdirNestedTest(),
        CpRecursiveTest(),
        ChmodTest(),
        LsTest(),

        // Archives
        TarListTest(),
        TarCreateExtractTest(),

        // Checksums / encoding
        Sha256Test(),
        Base64Test(),

        // Network (string-verified)
        PingCountTest(),
    ]

    // MARK: - Lookup

    private static let index: [String: any SandboxTestCase] = {
        var map: [String: any SandboxTestCase] = [:]
        for tc in all {
            for id in tc.rowIDs {
                map[id] = tc
            }
        }
        return map
    }()

    /// Returns the test case for `rowID`, or nil if no test covers that row.
    static func testCase(for rowID: String) -> (any SandboxTestCase)? {
        index[rowID]
    }
}
