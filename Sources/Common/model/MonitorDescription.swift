public enum MonitorDescription: Equatable, Sendable {
    case sequenceNumber(Int)
    case main
    case secondary
    case pattern(CaseInsensitiveRegex)

    public static func pattern(_ raw: String) -> MonitorDescription? {
        (try? CaseInsensitiveRegex(raw)).map(MonitorDescription.pattern)
    }
}

public func parseMonitorDescription(_ raw: String) throws(CmdParseError) -> MonitorDescription {
    if let int = Int(raw) {
        guard int >= 1 else { throw "Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal" }
        return .sequenceNumber(int)
    }
    return switch raw {
        case "main": .main
        case "secondary": .secondary
        case "": throw "Empty string is an illegal monitor description"
        default: .pattern(try CaseInsensitiveRegex(raw))
    }
}
