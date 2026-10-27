import Common

extension MonitorDescription {
    func resolveMonitor(sortedMonitors: [MonitorInfo]) -> MonitorInfo? {
        switch self {
            case .sequenceNumber(let number): sortedMonitors.getOrNil(atIndex: number - 1)
            case .main: mainMonitorInfo
            case .pattern(let regex): sortedMonitors.first { $0.name.contains(caseInsensitiveRegex: regex) }
            case .secondary:
                sortedMonitors.count == 2
                    ? sortedMonitors.first { $0.rect.topLeftCorner != mainMonitorInfo.rect.topLeftCorner }
                    : nil
        }
    }
}
