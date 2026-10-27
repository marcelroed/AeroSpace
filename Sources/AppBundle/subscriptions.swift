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

/// A client's events wait in its queue until its writer sends them. A client that stays connected but stops reading would
/// make its queue grow without end: past this many events, it's disconnected instead. Its `subscribe` exits, and a new
/// one starts from the current state. No event is dropped silently. Events follow the user's actions and new windows, so
/// a client this far behind is stuck
let maxQueuedEvents = 1000

/// A `subscribe` client: its events, encoded, queue up on the main actor as they happen, and one loop
/// (``sendEvents(of:)``) writes them, so the client gets them in order: the state when it subscribed, then every change
/// after it
struct Subscription {
    fileprivate let id = UUID()
    fileprivate let events: Set<ServerEventType>
    fileprivate let connection: NWConnection
    fileprivate let frames: AsyncStream<Data>
    fileprivate let queue: AsyncStream<Data>.Continuation

    fileprivate func send(_ frame: Data) {
        if case .dropped = queue.yield(frame) {
            queue.finish()
            connection.cancel() // Fails the pending write, which ends the writer
        }
    }
}

/// The clients whose writer hasn't ended
private(set) var subscriptions: [UUID: Subscription] = [:]

/// Queues the events of `args` from now on, after the current state unless `--no-send-initial`
func subscribe(_ args: SubscribeArgs, _ connection: NWConnection) -> Subscription {
    let (frames, queue) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(maxQueuedEvents))
    let subscription = Subscription(events: args.events, connection: connection, frames: frames, queue: queue)
    subscriptions[subscription.id] = subscription
    if args.sendInitial {
        for event in currentState(ServerEventType.allCases.filter(args.events.contains)) { subscription.send(encode(event)) }
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

/// Writes the queued events to the client until it disconnects, a write fails or its queue overflows. It runs on the main
/// actor, next to `subscriptions`, but a slow client never blocks it: each write suspends until the socket takes it
func sendEvents(of subscription: Subscription) async {
    defer { subscriptions[subscription.id] = nil }
    let (connection, queue) = (subscription.connection, subscription.queue)
    await withDiscardingTaskGroup { group in
        group.addTask { @Sendable in
            await connection.readTillError() // The client sends nothing: the end of its input means it disconnected
            queue.finish()
        }
        for await frame in subscription.frames {
            if await connection.writeFrame(frame).error != nil {
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

private func encode(_ event: ServerEvent) -> Data { Result { try jsonEncoder.encode(event) }.getOrDie() }

/// Encodes the event once for all its clients
func broadcastEvent(_ event: ServerEvent) {
    let receivers = subscriptions.values.filter { $0.events.contains(event.eventType) }
    if receivers.isEmpty { return }
    let frame = encode(event)
    for subscription in receivers { subscription.send(frame) }
}
