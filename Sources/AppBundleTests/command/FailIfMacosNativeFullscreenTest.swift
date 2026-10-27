@testable import AppBundle
import Common
import Testing

/// `--fail-if-macos-native-fullscreen` when the window's app doesn't answer (R2d L2)
@Suite(.aeroSpaceGlobalState)
struct FailIfMacosNativeFullscreenTest {
    @Test(arguments: ["focus", "move"])
    func aBusyAppsWindowIsFullscreenIfTheLastRefreshSawIt(command: String) async {
        let tree = "h_tiles(2) macos_fullscreen(*1)"
        setUpTree(tree)
        fake.answers[testApp.pid] = false // The AX timeout of a busy app
        expectEqual(await runCmd("\(command) --fail-if-macos-native-fullscreen right"), .fail())
        expectEqual(describeTree(), tree)
    }

    @Test
    func aBusyAppsWindowIsNotFullscreenIfTheLastRefreshDidntSeeIt() async {
        setUpTree("h_tiles(*1 2)")
        fake.answers[testApp.pid] = false
        expectEqual(await runCmd("focus --fail-if-macos-native-fullscreen right"), .ok)
        expectEqual(describeTree(), "h_tiles(1 *2)")
    }
}
