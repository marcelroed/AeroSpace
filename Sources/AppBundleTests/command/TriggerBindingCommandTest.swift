@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct TriggerBindingCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc("trigger-binding foo --mode main", TriggerBindingCommand(mode: "main", binding: "foo"))
        testParseSingleCommandSucc(
            "trigger-binding --mode main -- foo",
            TriggerBindingCommand(mode: "main", binding: "foo"),
        )
        testParseSingleCommandSucc(
            "trigger-binding --mode main -- --fail-if-noop",
            TriggerBindingCommand(mode: "main", binding: "--fail-if-noop"),
        )
    }

    @Test(arguments: [
        ("trigger-binding foo", "--mode flag is mandatory"),
        ("trigger-binding", "--mode flag is mandatory"), // The options are checked before the arguments
        ("trigger-binding --mode main --", "Argument '<binding>' is mandatory"),
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    @Test
    func unknownMode_listsAvailableModesSorted() async {
        // Ten modes, so that the dictionary order can't match the sorted order by chance (RB-13)
        let modeNames = ["main", "service", "resize", "move", "a", "z", "b", "y", "c", "x"]
        world.config.modes = Dictionary(uniqueKeysWithValues: modeNames.map { ($0, Mode(bindings: [:])) })

        let output = await runCmd("trigger-binding alt-h --mode unknown")
        expectEqual(output, .fail("Mode 'unknown' doesn't exist. Available modes: a,b,c,main,move,resize,service,x,y,z"))
    }
}
