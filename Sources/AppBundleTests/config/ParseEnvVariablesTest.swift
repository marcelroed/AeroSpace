@testable import AppBundle
import Common
import Testing

@MainActor
@Suite
struct ParseEnvVariablesTest: AeroSpaceTestSuite {
    @Test
    func testInterpolation() {
        testSucInterpolation("echo ${foo}", ["foo": "bar"], expected: "echo bar")
        testSucInterpolation("echo $foo", expected: "echo $foo")
        testSucInterpolation("echo $$foo", expected: "echo $$foo")
        testSucInterpolation("echo $${foo}", ["foo": "bar"], expected: "echo $bar")
        testSucInterpolation("echo $", expected: "echo $")

        testFailInterpolation("echo ${foo")
        testFailInterpolation("echo ${foo{bar}")
        testFailInterpolation("echo ${foo$bar}")
        testFailInterpolation("echo ${foo}")
    }

    @Test
    func testInterpolationResults() {
        let notPresented = { (name: String) in
            "Env variable '\(name)' isn't presented in AeroSpace.app env vars, or not available for interpolation (because it's mutated)"
        }
        assertEquals("".interpolate(with: [:]), .success(""))
        assertEquals("a${x}b${y}${x}$c".interpolate(with: ["x": "1", "y": "2"]), .success("a1b21$c"))
        assertEquals("${a} ${b} ${c}".interpolate(with: ["b": "B"]), .failure([notPresented("a"), notPresented("c")]))
        assertEquals("${a} ${b".interpolate(with: [:]), .failure(["Unbalanced curly braces"]))
    }

    @Test
    func testInherit() {
        let result1 = parseConfig("exec.inherit-env-vars = false")
        assertEquals(result1.errors, [])
        assertEquals(result1.config.execConfig.envVariables, [:])

        let result2 = parseConfig("exec.inherit-env-vars = true")
        assertEquals(result2.errors, [])
        assertEquals(result2.config.execConfig.envVariables, testEnv)
    }

    @Test
    func testAddVars() {
        let result = parseConfig(
            """
            [exec.env-vars]
            FOO = 'BAR'
            """,
        )
        assertEquals(result.errors, [])
        assertEquals(result.config.execConfig.envVariables, testEnv + ["FOO": "BAR"])
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
        assertEquals(errors, [
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
        assertEquals(errors, ["[ERROR] exec.env-vars.PWD: Changing 'PWD' is not allowed"])
    }

    @Test
    func testEnvVarsOfWrongType() {
        let errors = parseConfig("exec.env-vars = 1").strErrors
        assertEquals(errors, ["[ERROR] exec.env-vars: Expected type is 'Table'. But actual type is 'Int'"])
    }
}

private func testSucInterpolation(
    _ str: String,
    _ vars: [String: String] = [:],
    expected: String,
    fileID: String = #fileID,
    filePath: StaticString = #filePath,
    line: Int = #line,
    column: Int = #column,
) {
    switch str.interpolate(with: vars) {
        case .success(let actual): assertEquals(actual, expected, fileID: fileID, filePath: filePath, line: line, column: column)
        case .failure(let actual): assertEquals(actual, [], fileID: fileID, filePath: filePath, line: line, column: column)
    }
}

private func testFailInterpolation(_ str: String, _ vars: [String: String] = [:], fileID: String = #fileID, filePath: StaticString = #filePath, line: Int = #line, column: Int = #column) {
    switch str.interpolate(with: vars) {
        case .success(let actual): failExpectedActual(nil, actual, fileID: fileID, filePath: filePath, line: line, column: column)
        case .failure: break
    }
}
