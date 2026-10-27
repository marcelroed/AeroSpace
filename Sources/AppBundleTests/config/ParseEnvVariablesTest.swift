@testable import AppBundle
import Common
import Testing

@Suite
struct ParseEnvVariablesTest {
    @Test
    func testInterpolation() {
        #expect("echo ${foo}".interpolate(with: ["foo": "bar"]) == .success("echo bar"))
        #expect("echo $foo".interpolate(with: [:]) == .success("echo $foo"))
        #expect("echo $$foo".interpolate(with: [:]) == .success("echo $$foo"))
        #expect("echo $${foo}".interpolate(with: ["foo": "bar"]) == .success("echo $bar"))
        #expect("echo $".interpolate(with: [:]) == .success("echo $"))

        for str in ["echo ${foo", "echo ${foo{bar}", "echo ${foo$bar}", "echo ${foo}"] {
            if case .success(let actual) = str.interpolate(with: [:]) {
                Issue.record("\(str.singleQuoted) must fail to interpolate. Got: \(actual.singleQuoted)")
            }
        }
    }

    @Test
    func testInterpolationResults() {
        let notPresented = { (name: String) in
            "Env variable '\(name)' isn't presented in AeroSpace.app env vars, or not available for interpolation (because it's mutated)"
        }
        #expect("".interpolate(with: [:]) == .success(""))
        #expect("a${x}b${y}${x}$c".interpolate(with: ["x": "1", "y": "2"]) == .success("a1b21$c"))
        #expect("${a} ${b} ${c}".interpolate(with: ["b": "B"]) == .failure([notPresented("a"), notPresented("c")]))
        #expect("${a} ${b".interpolate(with: [:]) == .failure(["Unbalanced curly braces"]))
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
