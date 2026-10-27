@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct ListExecEnvVarsCommandTest {
    @Test
    func outputIsSortedByName() async {
        // Ten variables, so that the dictionary order can't match the sorted order by chance (RB-13)
        let names = ["PATH", "HOME", "LANG", "A", "Z", "B", "Y", "C", "X", "FOO"]
        config.execConfig.envVariables = Dictionary(uniqueKeysWithValues: names.map { ($0, "value-\($0)") })

        let output = await runCmd("list-exec-env-vars")
        #expect(output == CmdOutput(stdout: names.sorted().map { "\($0)=value-\($0)" }))
    }
}
