@testable import AppBundle
import Common
import Testing

@Suite
struct ParseEnvVariablesTest {
    @Test
    func testInterpolation() {
        expectEqual(interpolate("echo ${foo}", ["foo": "bar"]), Interpolation(result: "echo bar"))
        expectEqual(interpolate("echo $foo"), Interpolation(result: "echo $foo"))
        expectEqual(interpolate("echo $$foo"), Interpolation(result: "echo $$foo"))
        expectEqual(interpolate("echo $${foo}", ["foo": "bar"]), Interpolation(result: "echo $bar"))
        expectEqual(interpolate("echo $"), Interpolation(result: "echo $"))

        for str in ["echo ${foo", "echo ${foo{bar}", "echo ${foo$bar}", "echo ${foo}"] {
            let interpolation = interpolate(str)
            expectEqual(interpolation.result, nil, "\(str.singleQuoted) must fail to interpolate")
            #expect(!interpolation.errors.isEmpty, "\(str.singleQuoted) must report why it fails")
        }
    }

    @Test
    func testInterpolationResults() {
        let notPresented = { (name: String) in
            "Env variable '\(name)' isn't presented in AeroSpace.app env vars, or not available for interpolation (because it's mutated)"
        }
        expectEqual(interpolate(""), Interpolation(result: ""))
        expectEqual(interpolate("a${x}b${y}${x}$c", ["x": "1", "y": "2"]), Interpolation(result: "a1b21$c"))
        expectEqual(interpolate("${a} ${b} ${c}", ["b": "B"]), Interpolation(result: nil, errors: [notPresented("a"), notPresented("c")]))
        expectEqual(interpolate("${a} ${b"), Interpolation(result: nil, errors: ["Unbalanced curly braces"]))
    }

    private func interpolate(_ raw: String, _ variables: [String: String] = [:]) -> Interpolation {
        var d = Diagnostics()
        let result = AppBundle.interpolate(raw, with: variables, .emptyRoot, &d)
        return Interpolation(result: result, errors: d.errors.map(\.message))
    }

    @Test
    func testInherit() {
        let result1 = parseConfig("exec.inherit-env-vars = false")
        expectEqual(result1.errors, [])
        expectEqual(result1.config.execConfig.envVariables, [:])

        let result2 = parseConfig("exec.inherit-env-vars = true")
        expectEqual(result2.errors, [])
        expectEqual(result2.config.execConfig.envVariables, testEnv)
    }

    @Test
    func testAddVars() {
        let result = parseConfig(
            """
            [exec.env-vars]
            FOO = 'BAR'
            """,
        )
        expectEqual(result.errors, [])
        expectEqual(result.config.execConfig.envVariables, testEnv + ["FOO": "BAR"])
    }

    @Test
    func testCyclicDep() {
        let errors = parseConfig(
            """
            [exec.env-vars]
            FOO = '${BAR}'
            BAR = '${FOO}'
            """,
        ).strErrors
        expectEqual(errors, [
            "[ERROR] exec.env-vars.BAR: Env variable 'FOO' isn't presented in AeroSpace.app env vars, or not available for interpolation (because it's mutated)",
            "[ERROR] exec.env-vars.FOO: Env variable 'BAR' isn't presented in AeroSpace.app env vars, or not available for interpolation (because it's mutated)",
        ])
    }

    @Test
    func testForbidPwd() {
        let errors = parseConfig(
            """
            [exec.env-vars]
            PWD = ''
            """,
        ).strErrors
        expectEqual(errors, ["[ERROR] exec.env-vars.PWD: Changing 'PWD' is not allowed"])
    }

    @Test
    func testEnvVarsOfWrongType() {
        let errors = parseConfig("exec.env-vars = 1").strErrors
        expectEqual(errors, ["[ERROR] exec.env-vars: Expected type is 'Table'. But actual type is 'Int'"])
    }
}

/// The interpolated string, or nil, and the reported errors
private struct Interpolation: Equatable {
    var result: String?
    var errors: [String] = []
}
