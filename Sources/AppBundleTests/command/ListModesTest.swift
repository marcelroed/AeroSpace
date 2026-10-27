@testable import AppBundle
import Common
import Foundation
import Testing

@Suite(.aeroSpaceGlobalState)
struct ListModesTest {
    @Test
    func parseListModesCommand() {
        testParseSingleCommandSucc("list-modes", ListModesCommand())
        testParseSingleCommandSucc("list-modes --current", ListModesCommand(current: true))
        testParseSingleCommandSucc("list-modes --json", ListModesCommand(output: .json))
        testParseSingleCommandSucc("list-modes --count", ListModesCommand(output: .count))
        testParseSingleCommandSucc("list-modes --current --json", ListModesCommand(current: true, output: .json))
    }

    @Test
    func parseListModesCommandConflicts() {
        #expect(parseCommand("list-modes --json --count").errorOrNil == "Conflicting options: --count, --json")
        #expect(parseCommand("list-modes --current --count").errorOrNil == "Conflicting options: --count, --current")
    }

    @Test
    func listModesOutput() async {
        world.config.modes = [
            "main": Mode(bindings: [:]),
            "service": Mode(bindings: [:]),
            "resize": Mode(bindings: [:]),
        ]

        var output = await runCmd("list-modes")
        #expect(output == CmdOutput(stdout: ["main", "resize", "service"]))

        output = await runCmd("list-modes --current")
        #expect(output == CmdOutput(stdout: ["main"]))

        output = await runCmd("list-modes --count")
        #expect(output == CmdOutput(stdout: ["3"]))

        let expectedJson = JSONEncoder.aeroSpaceDefault.encodeToString([
            ["mode-id": "main"],
            ["mode-id": "resize"],
            ["mode-id": "service"],
        ])
        output = await runCmd("list-modes --json")
        #expect(output == CmdOutput(stdout: [expectedJson.orDie()]))

        let expectedCurrentJson = JSONEncoder.aeroSpaceDefault.encodeToString([["mode-id": "main"]])
        output = await runCmd("list-modes --current --json")
        #expect(output == CmdOutput(stdout: [expectedCurrentJson.orDie()]))
    }
}
