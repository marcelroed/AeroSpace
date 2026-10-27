public enum MonitorDescription: Equatable, Sendable {
    case sequenceNumber(Int)
    case main
    case secondary
    case pattern(CaseInsensitiveRegex)

    public static func pattern(_ raw: String) -> MonitorDescription? {
        switch CaseInsensitiveRegex.new(raw) {
            case .success(let regex): .pattern(regex)
            case .failure: nil
        }
    }
}

public func parseMonitorDescription(_ raw: String) -> ResOrStr<MonitorDescription> {
    if let int = Int(raw) {
        return int >= 1
            ? .success(.sequenceNumber(int))
            : .failure("Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal")
    }
    return switch raw {
        case "main": .success(.main)
        case "secondary": .success(.secondary)
        case "": .failure("Empty string is an illegal monitor description")
        default: CaseInsensitiveRegex.new(raw).map(MonitorDescription.pattern)
    }
}
