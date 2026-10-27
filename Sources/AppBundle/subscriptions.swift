import Common
import Foundation
import Network

private struct Subscriber {
    let connection: NWConnection
    let events: Set<ServerEventType>
}

/// The `subscribe` clients. A client stays until it disconnects or an event can't be written to it
private final class Subscribers {
    private var byId: [UUID: Subscriber] = [:]

    func add(_ subscriber: Subscriber) -> UUID {
        let id = UUID()
        byId[id] = subscriber
        return id
    }

    func remove(_ id: UUID) { byId.removeValue(forKey: id) }

    func broadcast(_ event: ServerEvent) async {
        for (id, subscriber) in byId where subscriber.events.contains(event.eventType) {
            if await subscriber.connection.writeAtomic(event, jsonEncoder).error != nil {
                remove(id)
            }
        }
    }
}

private let subscribers = Subscribers()

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

func handleSubscribeAndWaitTillError(_ connection: NWConnection, _ args: SubscribeArgs) async {
    let id = subscribers.add(Subscriber(connection: connection, events: args.events))
    defer { subscribers.remove(id) }
    if args.sendInitial {
        let f = focus
        for eventType in args.events {
            let event: ServerEvent
            switch eventType {
                case .focusChanged:
                    event = .focusChanged(windowId: f.windowOrNil?.windowId.raw, workspace: f.workspace.name)
                case .workspaceChanged:
                    event = .workspaceChanged(workspace: f.workspace.name, prevWorkspace: f.workspace.name)
                case .modeChanged:
                    event = .modeChanged(mode: world.activeMode)
                case .focusedMonitorChanged:
                    event = .focusedMonitorChanged(
                        workspace: f.workspace.name,
                        monitorId_oneBased: f.workspace.workspaceMonitor.monitorId_oneBased,
                    )
                case .windowDetected, .bindingTriggered: continue
            }
            if await connection.writeAtomic(event, jsonEncoder).error != nil {
                return
            }
        }
    }

    // Keep connection alive - wait for client to disconnect
    await connection.readTillError()
}

private let jsonEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
    return e
}()

func broadcastEvent(_ event: ServerEvent) {
    Task.startUnstructured { await subscribers.broadcast(event) }
}
