import AppKit
import Common

let testEnv = ["PATH": "AEROSPACE_TEST_PATH", "AEROSPACE_INHERITED_TEST_ENV": "inherited"]
private var env: [String: String] {
    isUnitTest ? testEnv : ProcessInfo.processInfo.environment
}

private let defaultOverriddenEnvVars = ["PATH": "/opt/homebrew/bin:/opt/homebrew/sbin:\(env["PATH"] ?? "")"]

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
        switch rawStr.interpolate(with: interpolationEnv) {
            case .success(let interpolated): result[key] = interpolated
            case .failure(let errors): for error in errors { d.error(path, error) }
        }
    }
    return result
}
