@testable import AppBundle
import Common
import Foundation
import Testing

@Suite
struct ParseEnvVariablesTest {
    @Test(arguments: [
        ("", [:], "", []),
        ("echo ${foo}", ["foo": "bar"], "echo bar", []),
        ("a${x}b${y}${x}$c", ["x": "1", "y": "2"], "a1b21$c", []),
        ("echo $foo", [:], "echo $foo", []),
        ("echo $$foo", [:], "echo $$foo", []),
        ("echo $${foo}", ["foo": "bar"], "echo $bar", []),
        ("echo $", [:], "echo $", []),
        ("${a} ${b} ${c}", ["b": "B"], nil, [notPresented("a"), notPresented("c")]),
        ("echo ${foo", [:], nil, ["Unbalanced curly braces"]),
        ("echo ${foo{bar}", [:], nil, ["Can't parse 'foo{' inside interpolation (Open curly brace is invalid character)"]),
        ("echo ${foo$bar}", [:], nil, ["Can't parse 'foo$' inside interpolation ('$' is disallowed character)"]),
    ] as [(String, [String: String], String?, [String])])
    func interpolation(raw: String, env: [String: String], result: String?, errors: [String]) {
        var d = Diagnostics()
        expectEqual(interpolate(raw, with: env, .emptyRoot, &d), result)
        expectEqual(d.errors.map(\.message), errors)
    }

    @Test(arguments: [
        // GUI apps don't have Homebrew's prefix in their PATH
        ("", ProcessInfo.processInfo.environment + ["PATH": "/opt/homebrew/bin:/opt/homebrew/sbin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "")]),
        ("exec.inherit-env-vars = false", [:]),
        ("exec.inherit-env-vars = true", ProcessInfo.processInfo.environment),
        ("exec.env-vars.FOO = 'BAR'", ProcessInfo.processInfo.environment + ["FOO": "BAR"]),
    ] as [(String, [String: String])])
    func envVars(toml: String, expectedEnv: [String: String]) {
        let result = parseConfig(toml)
        expectEqual(result.errors, [])
        expectEqual(result.config.execConfig.envVariables, expectedEnv)
    }

    @Test(arguments: [
        ("FOO = '${BAR}'\nBAR = '${FOO}'", [
            "[ERROR] exec.env-vars.BAR: \(notPresented("FOO"))",
            "[ERROR] exec.env-vars.FOO: \(notPresented("BAR"))",
        ]),
        ("PWD = ''", ["[ERROR] exec.env-vars.PWD: Changing 'PWD' is not allowed"]),
    ] as [(String, [String])])
    func envVarErrors(envVars: String, errors: [String]) {
        expectEqual(parseConfig("[exec.env-vars]\n" + envVars).strErrors, errors)
    }
}

nonisolated private func notPresented(_ name: String) -> String {
    "Env variable '\(name)' isn't presented in AeroSpace.app env vars, or not available for interpolation (because it's mutated)"
}
