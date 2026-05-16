import Foundation

/// Central registry of all sandbox test cases.
///
/// `all` is the single source of truth. To add a new test, implement
/// `SandboxTestCase` and add an instance here.
enum SandboxRegistry {

    static let all: [any SandboxTestCase] = [
        FindLargeFilesTest(),
        FindByNameTest(),
        FindEmptyTest(),
        GrepRecursiveTest(),
        GrepIgnoreCaseTest(),
        WordCountTest(),
        SortUniqCountTest(),
        AwkColumnTest(),
        TarListTest(),
        DiffFilesTest(),
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
