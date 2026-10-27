import Common

protocol AbstractApp: AnyObject, Hashable, AeroAny {
    nonisolated var pid: Int32 { get }
    var rawAppBundleId: String? { get }

    func getFocusedWindow(_ cm: CancellationMode) async throws -> Window?
    var name: String? { get }
    var execPath: String? { get }
    var bundlePath: String? { get }
}

extension AbstractApp {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        if lhs.pid == rhs.pid {
            check(lhs === rhs)
            return true
        } else {
            check(lhs !== rhs)
            return false
        }
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }
}
