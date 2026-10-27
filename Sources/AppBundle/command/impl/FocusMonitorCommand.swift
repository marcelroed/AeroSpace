import AppKit
import Common

struct FocusMonitorCommand: Command {
    let args: FocusMonitorCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let targetMonitor = args.target.val.resolve(target.workspace.workspaceMonitor, wrapAround: args.wrapAround)
            .getOrNil(appendErrorTo: &io.stderr) else { return .fail }
        return .from(bool: targetMonitor.activeWorkspace.focusWorkspace())
    }
}

extension MonitorTarget {
    @MainActor func resolve(_ currentMonitor: MonitorInfo, wrapAround: Bool) -> Result<MonitorInfo, String> {
        switch self {
            case .direction(let direction):
                guard let (monitorsInDirection, index) = currentMonitor.findRelativeMonitor(inDirection: direction) else {
                    return .failure("Should never happen. Can't find the current monitor")
                }
                return (wrapAround ? monitorsInDirection.get(wrappingIndex: index) : monitorsInDirection.getOrNil(atIndex: index))
                    .toResult("No monitors in direction \(direction)")
            case .relative(let nextPrev):
                let monitors = sortedMonitorInfos
                guard let curIndex = monitors.firstIndex(where: { $0.rect.topLeftCorner == currentMonitor.rect.topLeftCorner }) else {
                    return .failure("Can't find current monitor")
                }
                let targetIndex = nextPrev == .next ? curIndex + 1 : curIndex - 1
                return (wrapAround ? monitors.get(wrappingIndex: targetIndex) : monitors.getOrNil(atIndex: targetIndex))
                    .toResult("Can't find target monitor")
            case .patterns(let patterns):
                let monitors = sortedMonitorInfos
                return patterns.lazy.compactMap { $0.resolveMonitor(sortedMonitors: monitors) }.first
                    .toResult("None of the monitors match the pattern(s)")
        }
    }
}

extension MonitorInfo {
    func relation(to monitor: MonitorInfo) -> Orientation {
        guard let otherYRange = monitor.rect.minY.until(excl: monitor.rect.maxY) else { return .h }
        guard let myYRange = rect.minY.until(excl: rect.maxY) else { return .h }
        return myYRange.overlaps(otherYRange) ? .h : .v
    }

    func findRelativeMonitor(inDirection direction: CardinalDirection) -> (monitorsInDirection: [MonitorInfo], index: Int)? {
        let currentMonitor = self
        let monitors = sortedMonitorInfos.filter {
            currentMonitor.rect.topLeftCorner == $0.rect.topLeftCorner ||
                $0.relation(to: currentMonitor) == direction.orientation
        }
        guard let index = monitors.firstIndex(where: { $0.rect.topLeftCorner == currentMonitor.rect.topLeftCorner }) else { return nil }
        return (monitors, index + direction.focusOffset)
    }
}
