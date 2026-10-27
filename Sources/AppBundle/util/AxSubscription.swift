import AppKit
import Common

/// An AX observer of one element (the app or one of its windows). It's active while this object is alive. Only ``AxApp``
/// creates and holds it, so it's created and destroyed on the app's thread, and its source is on that thread's run loop
nonisolated final class AxSubscription {
    private let observer: AXObserver
    private let element: AXUIElement
    private let runLoop: CFRunLoop = CFRunLoopGetCurrent()
    private var notifications: [String] = []

    private init(_ observer: AXObserver, _ element: AXUIElement) {
        self.observer = observer
        self.element = element
    }

    /// nil if any of the notifications fails: an element is observed fully or not at all
    static func subscribe(_ element: AXUIElement, _ notifications: [String], _ app: AxApp) -> AxSubscription? {
        var observer: AXObserver?
        guard unsafe AXObserverCreate(app.pid, axObserverCallback, &observer) == .success, let observer else { return nil }
        let subscription = AxSubscription(observer, element)
        // Unretained (P8): the actor removes its subscriptions in its isolated deinit, on this thread, before it's freed
        let refcon = unsafe Unmanaged.passUnretained(app).toOpaque()
        for notification in notifications {
            // On failure, deinit removes the notifications added so far
            guard unsafe AXObserverAddNotification(observer, element, notification as CFString, refcon) == .success else { return nil }
            subscription.notifications.append(notification)
        }
        CFRunLoopAddSource(subscription.runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
        return subscription
    }

    deinit {
        CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
        for notification in notifications {
            AXObserverRemoveNotification(observer, element, notification as CFString)
        }
    }
}
