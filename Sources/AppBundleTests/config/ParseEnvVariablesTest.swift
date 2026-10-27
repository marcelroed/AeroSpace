@testable import AppBundle
import Common
import Testing

@Suite
struct ParseEnvVariablesTest {
    @Test
    func testInterpolation() {
        #expect(interpolate("echo ${foo}", ["foo": "bar"]) == ("echo bar", []))
        #expect(interpolate("echo $foo") == ("echo $foo", []))
        #expect(interpolate("echo $$foo") == ("echo $$foo", []))
        #expect(interpolate("echo $${foo}", ["foo": "bar"]) == ("echo $bar", []))
        #expect(interpolate("echo $") == ("echo $", []))

        for str in ["echo ${foo", "echo ${foo{bar}", "echo ${foo$bar}", "echo ${foo}"] {
            let (result, errors) = interpolate(str)
            #expect(result == nil, "\(str.singleQuoted) must fail to interpolate")
            #expect(!errors.isEmpty, "\(str.singleQuoted) must report why it fails")
        }
    }

    @Test
    func testInterpolationResults() {
        let notPresented = { (name: String) in
            "Env variable '\(name)' isn't presented in AeroSpace.app env vars, or not available for interpolation (because it's mutated)"
        }
        #expect(interpolate("") == ("", []))
        #expect(interpolate("a${x}b${y}${x}$c", ["x": "1", "y": "2"]) == ("a1b21$c", []))
        #expect(interpolate("${a} ${b} ${c}", ["b": "B"]) == (nil, [notPresented("a"), notPresented("c")]))
        #expect(interpolate("${a} ${b") == (nil, ["Unbalanced curly braces"]))
    }

    /// The interpolated string, or nil, and the reported errors
    private func interpolate(_ raw: String, _ variables: [String: String] = [:]) -> (String?, [String]) {
        var d = Diagnostics()
        let result = AppBundle.interpolate(raw, with: variables, .emptyRoot, &d)
        return (result, d.errors.map(\.message))
    }

    @Test
    func testInherit() {
        let result1 = parseConfig("exec.inherit-env-vars = false")
        #expect(result1.errors == [])
        #expect(result1.config.execConfig.envVariables == [:])

        let result2 = parseConfig("exec.inherit-env-vars = true")
        #expect(result2.errors == [])
        #expect(result2.config.execConfig.envVariables == testEnv)
    }

    @Test
    func testAddVars() {
        let result = parseConfig(
            """
            [exec.env-vars]
            FOO = 'BAR'
            """,
        )
        #expect(result.errors == [])
        #expect(result.config.execConfig.envVariables == testEnv + ["FOO": "BAR"])
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
        #expect(errors == [
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
        #expect(errors == ["[ERROR] exec.env-vars.PWD: Changing 'PWD' is not allowed"])
    }

    @Test
    func testEnvVarsOfWrongType() {
        let errors = parseConfig("exec.env-vars = 1").strErrors
        #expect(errors == ["[ERROR] exec.env-vars: Expected type is 'Table'. But actual type is 'Int'"])
    }
}
