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

        await assertRun("list-exec-env-vars", exitCode: 0, stdout: names.sorted().map { "\($0)=value-\($0)" }, stderr: [])
    }
}
