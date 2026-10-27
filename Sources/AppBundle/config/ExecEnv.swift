import AppKit
import Common

let testEnv: [String: String] = ["PATH": "AEROSPACE_TEST_PATH", "AEROSPACE_INHERITED_TEST_ENV": "inherited"]
private var env: [String: String] {
    isUnitTest ? testEnv : ProcessInfo.processInfo.environment
}

private let defaultOverriddenEnvVars: [String: String] = ["PATH": "/opt/homebrew/bin:/opt/homebrew/sbin:\(env["PATH"] ?? "")"]

struct ExecConfig: Equatable {
    var envVariables: [String: String] = env + defaultOverriddenEnvVars
}

private struct RawExecConfig {
    var inheritEnvVariables = true
    // Already interpolated value of overridden vars
    var overriddenVars: [String: String] = [:]
}

private let execFields: [String: Field<RawExecConfig>] = [
    "inherit-env-vars": Field(\.inheritEnvVariables, decodeBool),
    "env-vars": Field(\.overriddenVars, decodeEnvVariables),
]

/// Unlike the default `ExecConfig()`, an `exec` table without `env-vars` (or of a wrong type) drops the homebrew PATH
let decodeExecConfig: Decode<ExecConfig> = { raw, path, d in
    var exec = RawExecConfig()
    decodeTable(raw, into: &exec, execFields, path, &d)
    return ExecConfig(envVariables: (exec.inheritEnvVariables ? env : [:]) + exec.overriddenVars)
}

private let decodeEnvVariables: Decode<[String: String]> = { raw, path, d in
    guard let table = raw.asDictOrNil else {
        d.typeMismatch(path, expected: .table, actual: raw)
        return nil
    }
    let mutated = table.keys
    let fullEnv: [String: String] = env
    let baseEnv: [String: String] = fullEnv.filter { (key, _) -> Bool in !mutated.contains(key) }
    var result: [String: String] = [:]
    for (key, value) in table {
        let path = path + .key(key)
        if key == "PWD" { d.error(path, "Changing 'PWD' is not allowed") }
        guard let rawStr = decodeString(value, path, &d) else { continue }
        var interpolationEnv = baseEnv
        if let add: String = fullEnv[key] {
            interpolationEnv[key] = add
        }
        if let interpolated = interpolate(rawStr, with: interpolationEnv, path, &d) {
            result[key] = interpolated
        }
    }
    return result
}

/// `raw` with the `${name}` variables replaced, or nil after reporting each unknown variable
func interpolate(_ raw: String, with variables: [String: String], _ path: ConfigBacktrace, _ d: inout Diagnostics) -> String? {
    let tokens: [InterToken<String>]
    do {
        tokens = try raw.rawInterpolationTokens(interpolationChar: "$")
    } catch {
        d.error(path, error.message)
        return nil
    }
    var result = ""
    var isComplete = true
    for token in tokens {
        switch token {
            case .literal(let literal): result += literal
            case .interVar(let name):
                if let value = variables[name] {
                    result += value
                } else {
                    d.error(path, "Env variable '\(name)' isn't presented in AeroSpace.app env vars, "
                        + "or not available for interpolation (because it's mutated)")
                    isComplete = false
                }
        }
    }
    return isComplete ? result : nil
}
