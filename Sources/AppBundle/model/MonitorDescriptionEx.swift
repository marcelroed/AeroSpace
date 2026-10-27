import Common

extension MonitorDescription {
    /// The matching monitor of the current snapshot
    func resolveMonitor() -> MonitorInfo? {
        let monitors = world.monitors
        return switch self {
            case .sequenceNumber(let number): (1 ... monitors.all.count).contains(number) ? monitors.all[number - 1] : nil
            case .main: monitors.main
            case .pattern(let regex): monitors.all.first(where: { $0.name.contains(caseInsensitiveRegex: regex) })
            case .secondary:
                monitors.all.count == 2
                    ? monitors.all.first(where: { $0.rect.topLeftCorner != monitors.main.rect.topLeftCorner })
                    : nil
        }
    }
}
