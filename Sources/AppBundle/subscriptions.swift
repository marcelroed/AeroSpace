import Common
import Foundation
import Network

/// The args of `subscribe`. It's not a `Command`: it holds the connection open, and only the CLI can run it
struct SubscribeArgs: Equatable, Sendable {
    var events: Set<ServerEventType>
    var sendInitial = true

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var all = false
        var sendInitial = true
        while let option = try a.nextOption() {
            switch option {
                case "--all": all = true
                case "--no-send-initial": sendInitial = false
                default: throw .unknownOption(option)
            }
        }
        var events: Set<ServerEventType> = []
        var duplicate: String? = nil
        for arg in a.allPositionals() {
            if !events.insert(try parseEnum(arg)).inserted { duplicate = duplicate ?? arg }
        }
        if let duplicate { throw "Duplicate event '\(duplicate)'" }
        if !all && events.isEmpty { throw "Either --all or at least one <event> must be specified" }
        if all && !events.isEmpty { throw "--all conflicts with specifying individual events" }
        return Self(events: all ? Set(ServerEventType.allCases) : events, sendInitial: sendInitial)
    }
}

/// The queue of a `subscribe` client's events. The events are queued on the main actor as they happen, and written to
/// the client by one loop (``sendEvents(of:to:)``), so the client gets them in order: the state when it subscribed, then
/// every change after it
struct Subscription {
    fileprivate let id = UUID()
    fileprivate let events: AsyncStream<ServerEvent>
    fileprivate let queue: AsyncStream<ServerEvent>.Continuation
}

private var subscribers: [UUID: (events: Set<ServerEventType>, queue: AsyncStream<ServerEvent>.Continuation)] = [:]

/// Queues the events of `args` from now on, after the current state unless `--no-send-initial`
func subscribe(_ args: SubscribeArgs) -> Subscription {
    let (events, queue) = AsyncStream<ServerEvent>.makeStream()
    let subscription = Subscription(events: events, queue: queue)
    subscribers[subscription.id] = (args.events, queue)
    if args.sendInitial {
        for event in currentState(ServerEventType.allCases.filter(args.events.contains)) { queue.yield(event) }
    }
    return subscription
}

/// The current state as events of `types`. Detections and key presses have no current state
private func currentState(_ types: [ServerEventType]) -> [ServerEvent] {
    let f = focus
    return types.compactMap { (type: ServerEventType) -> ServerEvent? in
        switch type {
            case .focusChanged: .focusChanged(windowId: f.windowOrNil?.windowId.raw, workspace: f.workspace.name)
            case .focusedMonitorChanged:
                .focusedMonitorChanged(workspace: f.workspace.name, monitorId_oneBased: f.workspace.workspaceMonitor.monitorId_oneBased)
            case .workspaceChanged: .workspaceChanged(workspace: f.workspace.name, prevWorkspace: f.workspace.name)
            case .modeChanged: .modeChanged(mode: world.activeMode)
            case .windowDetected, .bindingTriggered: nil
        }
    }
}

/// Writes the queued events to the client until it disconnects or a write fails
func sendEvents(of subscription: Subscription, to connection: NWConnection) async {
    defer { subscribers[subscription.id] = nil }
    let queue = subscription.queue
    await withDiscardingTaskGroup { group in
        group.addTask { @Sendable in
            await connection.readTillError() // The client sends nothing: the end of its input means it disconnected
            queue.finish()
        }
        for await event in subscription.events {
            if await connection.writeAtomic(event, jsonEncoder).error != nil {
                connection.cancel() // Ends readTillError
                break
            }
        }
    }
}

private let jsonEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
    return e
}()

func broadcastEvent(_ event: ServerEvent) {
    for subscriber in subscribers.values where subscriber.events.contains(event.eventType) {
        subscriber.queue.yield(event)
    }
}
