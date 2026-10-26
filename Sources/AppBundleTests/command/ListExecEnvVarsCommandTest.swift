@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct ListExecEnvVarsCommandTest: AeroSpaceTestSuite {
    @Test
    func testOutputIsSortedByName() async {
        // Ten variables, so that the dictionary order can't match the sorted order by chance (RB-13)
        let names = ["PATH", "HOME", "LANG", "A", "Z", "B", "Y", "C", "X", "FOO"]
        config.execConfig.envVariables = Dictionary(uniqueKeysWithValues: names.map { ($0, "value-\($0)") })

        let result = await parseCommand("list-exec-env-vars").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertEquals(result.stdout, names.sorted().map { "\($0)=value-\($0)" })
    }
}
