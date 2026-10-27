import AppKit
import Common

/// The subscription is active as long as you keep this class in memory
final class AxSubscription {
    private let obs: AXObserver
    private let ax: AXUIElement
    private let axThreadToken: AxAppThreadToken = axTaskLocalAppThreadToken ?? dieT("axTaskLocalAppThreadToken is not initialized")
    private var notifKeys: Set<String> = []

    private init(obs: AXObserver, ax: AXUIElement) {
        self.obs = obs
        self.ax = ax
    }

    private func subscribe(_ key: String) -> Bool {
        axThreadToken.checkEquals(axTaskLocalAppThreadToken)
        guard AXObserverAddNotification(obs, ax, key as CFString, nil) == .success else { return false }
        notifKeys.insert(key)
        return true
    }

    static func bulkSubscribe(
        _ nsApp: NSRunningApplication,
        _ ax: AXUIElement,
        _ job: RunLoopJob,
        _ handlerToNotifKeyMapping: HandlerToNotifKeyMapping,
    ) throws -> [AxSubscription] {
        var result: [AxSubscription] = []
        var visitedNotifKeys: Set<String> = []
        for unsafe (handler, notifKeys) in unsafe handlerToNotifKeyMapping {
            try job.checkCancellation()
            var obs: AXObserver?
            guard unsafe AXObserverCreate(nsApp.processIdentifier, handler, &obs) == .success, let obs else { return [] }
            let subscription = AxSubscription(obs: obs, ax: ax)
            for key in notifKeys {
                try job.checkCancellation()
                assert(visitedNotifKeys.insert(key).inserted)
                if !subscription.subscribe(key) { return [] }
            }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
            result.append(subscription)
        }
        return result
    }

    deinit {
        axThreadToken.checkEquals(axTaskLocalAppThreadToken)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        for notifKey in notifKeys {
            AXObserverRemoveNotification(obs, ax, notifKey as CFString)
        }
    }
}

typealias HandlerToNotifKeyMapping = [(AXObserverCallback, [String])]
