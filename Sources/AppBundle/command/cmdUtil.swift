import Common

nonisolated enum ToggleEnum: String, CaseIterable, Sendable {
    case on, off, toggle

    func resolve(current: Bool) -> Bool {
        switch self {
            case .on: true
            case .off: false
            case .toggle: !current
        }
    }
}

/// `on` or `off`
nonisolated enum OnOff: String, CaseIterable, Sendable {
    case on, off

    var toggle: ToggleEnum {
        switch self {
            case .on: .on
            case .off: .off
        }
    }
}

extension DfsNextPrev {
    var indexOffset: Int {
        switch self {
            case .dfsNext: 1
            case .dfsPrev: -1
        }
    }
}
