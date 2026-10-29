/// https://github.com/swiftlang/swift-experimental-string-processing/issues/792
/// https://forums.swift.org/t/should-regex-be-sendable/69529
public struct CaseInsensitiveRegex: Equatable, Sendable {
    public let origin: String
    fileprivate nonisolated(unsafe) let regex: Regex<AnyRegexOutput>

    public init(_ origin: String) throws(CmdParseError) {
        let regex: Regex<AnyRegexOutput>
        do {
            regex = try Regex(origin)
        } catch {
            throw "Can't parse \(origin.singleQuoted) regex: \(error)" // localizedDescription is a generic text with an unstable type name
        }
        self.origin = origin
        unsafe self.regex = regex.ignoresCase()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.origin == rhs.origin }
}

extension String {
    @MainActor public func contains(caseInsensitiveRegex regex: CaseInsensitiveRegex) -> Bool {
        self.contains(unsafe regex.regex)
    }
}
