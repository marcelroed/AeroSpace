@testable import AppBundle
import Common
import XCTest

@MainActor
final class ListModesTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParseListModesCommand() {
        testParseSingleCommandSucc("list-modes", ListModesCmdArgs(rawArgs: []))
        testParseSingleCommandSucc("list-modes --current", ListModesCmdArgs(rawArgs: []).copy(\.current, true))
        testParseSingleCommandSucc("list-modes --json", ListModesCmdArgs(rawArgs: []).copy(\.json, true))
        testParseSingleCommandSucc("list-modes --count", ListModesCmdArgs(rawArgs: []).copy(\.outputOnlyCount, true))
        testParseSingleCommandSucc("list-modes --current --json", ListModesCmdArgs(rawArgs: []).copy(\.current, true).copy(\.json, true))
    }

    func testParseListModesCommandConflicts() {
        assertEquals(parseCommand("list-modes --json --count").errorOrNil, "ERROR: Conflicting options: --count, --json")
        assertEquals(parseCommand("list-modes --current --count").errorOrNil, "ERROR: Conflicting options: --count, --current")
    }

    func testListModesOutput() async {
        config.modes = [
            "main": Mode(bindings: [:]),
            "service": Mode(bindings: [:]),
            "resize": Mode(bindings: [:]),
        ]

        await assertRun("list-modes", exitCode: 0, stdout: ["main", "resize", "service"], stderr: [])

        await assertRun("list-modes --current", exitCode: 0, stdout: ["main"], stderr: [])

        await assertRun("list-modes --count", exitCode: 0, stdout: ["3"], stderr: [])

        let expectedJson = JSONEncoder.aeroSpaceDefault.encodeToString([
            ["mode-id": "main"],
            ["mode-id": "resize"],
            ["mode-id": "service"],
        ])
        await assertRun("list-modes --json", exitCode: 0, stdout: [expectedJson.orDie()], stderr: [])

        let expectedCurrentJson = JSONEncoder.aeroSpaceDefault.encodeToString([["mode-id": "main"]])
        await assertRun("list-modes --current --json", exitCode: 0, stdout: [expectedCurrentJson.orDie()], stderr: [])
    }
}
