@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct TestCommandTest {
    /// Workspace a, `h_tiles(*1)`, is focused, b is `h_tiles(2)`, and c is empty. `workspaceEnv` is AEROSPACE_WORKSPACE.
    /// Exit code 1 without output is false
    @Test(arguments: [
        ("test %{window-id} = 1", nil, .ok),
        ("test %{window-id} = 2", nil, CmdOutput(exitCode: 1)),
        ("test %{window-id} = abc", nil, .fail("Can't convert String 'abc' to Int")),
        ("test %{window-id} ~= 1", nil, .fail("Interpolation variable: 'window-id' has a type of Int. The Int type is not compatible with '~=' operator.")),
        ("test %{workspace-is-focused} = true", nil, .ok),
        ("test %{workspace-is-focused} = false", nil, CmdOutput(exitCode: 1)),
        ("test %{workspace-is-focused} = foo", nil, .fail("Can't convert String 'foo' to Bool")),
        (
            "test %{workspace-is-focused} ~= foo", nil,
            .fail("Interpolation variable: 'workspace-is-focused' has a type of Bool. The Bool type is not compatible with '~=' operator."),
        ),
        ("test %{app-bundle-id} = bobko.AeroSpace.test-app", nil, .ok),
        ("test %{app-bundle-id} = other.bundle.id", nil, CmdOutput(exitCode: 1)),
        ("test %{app-bundle-id} ~= AERO", nil, .ok), // Case-insensitive, and not anchored
        ("test %{app-bundle-id} ~= zzzzz", nil, CmdOutput(exitCode: 1)),
        ("test %{app-bundle-id} ~= [", nil, .fail("Can't parse '[' regex: expected custom character class members")),
        ("test %{workspace} = a", nil, .ok),

        ("test-not %{window-id} = 1", nil, CmdOutput(exitCode: 1)),
        ("test-not %{window-id} = 2", nil, .ok),
        ("test-not %{workspace-is-focused} = foo", nil, .fail("Can't convert String 'foo' to Bool")), // A failure isn't inverted

        // AEROSPACE_WORKSPACE makes `test` look at that workspace and its window, not at the focused ones
        ("test %{workspace} = b", "b", .ok),
        ("test %{workspace-is-focused} = false", "b", .ok),
        ("test %{window-id} = 2", "b", .ok),
        // Without a window, the variables are about the workspace
        ("test %{workspace-is-visible} = false", "c", .ok),
        ("test %{window-id} = 1", "c", .fail(noWindowIsFocused)),

        ("test", nil, .fail("Argument '<lhs>' is mandatory")),
        ("test %{app-bundle-id}", nil, .fail("Argument '<operator>' is mandatory")),
        ("test %{app-bundle-id} =", nil, .fail("Argument '<rhs>' is mandatory")),
        ("test %{foo} = foo", nil, .fail("Can't parse 'foo'.\nPossible values: \(lhsValues)")),
        ("test %{newline} = foo", nil, .fail("Can't parse 'newline'.\nPossible values: \(lhsValues)")), // Not a formatting variable
        ("test foo = foo", nil, .fail("Left hand side must be a single interpolation variable")),
        ("test-not foo%{app-bundle-id} = foo", nil, .fail("Left hand side must be a single interpolation variable")),
        ("test %{app-bundle-id} = %{app-bundle-id}", nil, .fail("Right hand side doesn't allow interpolation variables")),
        ("test %{window-id} = %{invalid}", nil, .fail("Right hand side doesn't allow interpolation variables")),
        ("test %{window-id} '!=' 1", nil, .fail("Can't parse '!='.\nPossible values: \(TestCommand.InfixOperator.unionLiteral)")),
    ] as [(String, String?, CmdOutput)])
    func run(command: String, workspaceEnv: String?, expected: CmdOutput) async {
        setUpTree("h_tiles(*1)", workspace: "a")
        setUpTree("h_tiles(2)", workspace: "b")
        expectEqual(await runCmd(command, workspaceEnv: workspaceEnv), expected)
    }
}

/// The variables about an object: the left hand side can't be a formatting variable
nonisolated private let lhsValues = "(" + FormatVar.allCases.filter { $0.subject != nil }.map(\.rawValue).joined(separator: "|") + ")"
