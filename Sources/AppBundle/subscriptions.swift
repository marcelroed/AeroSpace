import Common
import Foundation
import Network

private struct Subscriber {
    let connection: NWConnection
    let events: Set<ServerEventType>
}

private var subscribers: [UUID: Subscriber] = [:]

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
    let id = UUID()
    subscribers[id] = Subscriber(connection: connection, events: args.events)
    defer { subscribers.removeValue(forKey: id) }
    if args.sendInitial {
        let f = focus
        for eventType in args.events {
            let event: ServerEvent
            switch eventType {
                case .focusChanged:
                    event = .focusChanged(windowId: f.windowOrNil?.windowId, workspace: f.workspace.name)
                case .workspaceChanged:
                    event = .workspaceChanged(workspace: f.workspace.name, prevWorkspace: f.workspace.name)
                case .modeChanged:
                    event = .modeChanged(mode: activeMode)
                case .focusedMonitorChanged:
                    event = .focusedMonitorChanged(
                        workspace: f.workspace.name,
                        monitorId_oneBased: f.workspace.workspaceMonitor.monitorId_oneBased ?? 0,
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
    Task.startUnstructured {
        for (id, subscriber) in subscribers {
            guard subscriber.events.contains(event.eventType) else { continue }
            if await subscriber.connection.writeAtomic(event, jsonEncoder).error != nil {
                _ = subscribers.removeValue(forKey: id)
            }
        }
    }
}
