@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct ResizeCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc("resize smart +10", ResizeCommand(dimension: .smart, units: .add(10)))
        testParseSingleCommandSucc("resize smart -10", ResizeCommand(dimension: .smart, units: .subtract(10)))
        testParseSingleCommandSucc("resize smart 10", ResizeCommand(dimension: .smart, units: .set(10)))

        testParseSingleCommandSucc("resize smart-opposite +10", ResizeCommand(dimension: .smartOpposite, units: .add(10)))
        testParseSingleCommandSucc("resize smart-opposite -10", ResizeCommand(dimension: .smartOpposite, units: .subtract(10)))
        testParseSingleCommandSucc("resize smart-opposite 10", ResizeCommand(dimension: .smartOpposite, units: .set(10)))

        testParseSingleCommandSucc("resize height 10", ResizeCommand(dimension: .height, units: .set(10)))
        testParseSingleCommandSucc("resize width 10", ResizeCommand(dimension: .width, units: .set(10)))
    }

    @Test(arguments: [
        ("resize s 10", "Can't parse 's'.\nPossible values: (width|height|smart|smart-opposite)"),
        ("resize smart foo", "<number> argument must be a number"),
        // RB-33: UInt(...) accepts a sign too, so `+-10` and `++10` used to mean `+10`
        ("resize smart +-10", "<number> argument must be a number"),
        ("resize smart ++10", "<number> argument must be a number"),
        ("resize smart +-0", "<number> argument must be a number"),
        ("resize smart +", "<number> argument must be a number"),
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        #expect(output == .fail(error))
    }

    @Test(arguments: [
        // The diff is split between the siblings: 2 / (3 - 1) = 1
        ("h_tiles(*1:4 2:4 3:4)", "resize width +2", "h_tiles(*1:6 2:3 3:3)"),
        ("h_tiles(*1:4 2:4 3:4)", "resize width -2", "h_tiles(*1:2 2:5 3:5)"),
        ("h_tiles(*1:4 2:4 3:4)", "resize width 6", "h_tiles(*1:6 2:3 3:3)"), // diff = 6 - 4
        // height climbs to the vertical container
        ("h_tiles(0 v_tiles(*1:4 2:4))", "resize height +2", "h_tiles(0:1 v_tiles:1(*1:6 2:2))"),
        // smart resizes along the axis of the parent, even if an ancestor qualifies too
        ("h_tiles(v_tiles:4(*1:4 2:4) 3:4)", "resize smart +2", "h_tiles(v_tiles:4(*1:6 2:2) 3:4)"),
        // smart-opposite climbs to the ancestor with the opposite orientation and resizes its child on the path
        ("h_tiles(v_tiles:4(*1 2) 3:4)", "resize smart-opposite +2", "h_tiles(v_tiles:6(*1:1 2:1) 3:2)"),
    ])
    func succeeds(before: String, command: String, after: String) async {
        setUpTree(before)
        let output = await runCmd(command)
        #expect(output == .ok)
        #expect(describeTree(weights: true) == after)
    }

    @Test(arguments: [
        ("h_tiles(*1 2)", "resize height +2", "Can't resize: the window isn't inside a vertical tiles container"), // Not "floating windows"
        ("h_accordion(*1 2)", "resize smart +2", "Can't resize: the window isn't inside a tiles container"),
        ("h_tiles(2) floating(*1)", "resize width +2", "resize command doesn't support floating windows yet https://github.com/nikitabobko/AeroSpace/issues/9"),
        ("h_tiles()", "resize width +2", "No window is focused"),
        ("h_tiles(*1:4)", "resize width +2", "Can't resize: there are no other tiling windows to the left or right"), // RB-67
    ])
    func fails(tree: String, command: String, error: String) async {
        setUpTree(tree)
        let before = describeTree(weights: true)
        let output = await runCmd(command)
        #expect(output == .fail(error))
        #expect(describeTree(weights: true) == before)
    }
}
