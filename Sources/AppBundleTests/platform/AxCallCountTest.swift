@testable import AppBundle
import AppKit
import Common
import Foundation
import Testing

/// The AX work of the common scenarios on a realistic world: FakePlatform's call log, and the AX calls that LivePlatform
/// makes for it (``Phase/cost``). `AX_CALL_TABLE=1 swift test --filter AxCallCountTest` prints the table,
/// `AX_CALL_TABLE=<file>` writes it. It asserts only invariants: the counts are expected to change
@Suite(.aeroSpaceGlobalState)
struct AxCallCountTest {
    @Test
    func scenarios() async throws {
        var results: [(scenario: String, phases: [Phase], convergence: Convergence)] = []
        for scenario in allScenarios {
            setUpWorkspacesForTests()
            setUpRealisticWorld()
            let phases: [Phase] = try await scenario.run()
            results.append((scenario.name, phases, await convergence()))
        }
        for (scenario, phases, convergence) in results {
            expectEqual(convergence.notBack, [], "\(scenario): moved behind AeroSpace's back")
            for phase in phases {
                expectEqual(phase.waste.focusOfFocused, 0, "\(scenario): \(phase.name)")
                expectEqual(phase.waste.unhideOfVisible, 0, "\(scenario): \(phase.name)")
                // A frame write that leaves the window where it was makes the app lay it out again for nothing
                expectEqual(phase.waste.sameFrame, [:], "\(scenario): \(phase.name)")
                if !phase.isIdle { continue }
                // An idle phase only reads: no frame writes, parks or focus
                expectEqual(phase.calls.filter(\.isEffect), [], "\(scenario): \(phase.name)")
            }
        }
        let idle = results.first { $0.scenario == idleScenario }?.phases ?? []
        expectEqual(idle.count, 2)
        expectEqual(idle.first?.calls, idle.last?.calls) // The heavy refresh converged: the next one does the same
        if let destination = ProcessInfo.processInfo.environment["AX_CALL_TABLE"] {
            let table = axCallTable(results)
            if destination == "1" {
                print(table)
            } else {
                try table.write(toFile: destination, atomically: true, encoding: .utf8)
            }
        }
    }
}

// MARK: The world

private let terminal = AppInfo(pid: 101, bundleId: "test.terminal", name: "Terminal", execPath: nil, bundlePath: nil)
private let browser = AppInfo(pid: 102, bundleId: "test.browser", name: "Browser", execPath: nil, bundlePath: nil)
private let editor = AppInfo(pid: 103, bundleId: "test.editor", name: "Editor", execPath: nil, bundlePath: nil)
private let chat = AppInfo(pid: 104, bundleId: "test.chat", name: "Chat", execPath: nil, bundlePath: nil)
/// Hidden (cmd-h) from the start
private let music = AppInfo(pid: 105, bundleId: "test.music", name: "Music", execPath: nil, bundlePath: nil)
private let finder = AppInfo(pid: 106, bundleId: "test.finder", name: "Finder", execPath: nil, bundlePath: nil)

private let worldDescription = """
    Two monitors, 6 apps, 12 windows (window ids; `*` has the focus), the default normalizations:
    - workspace 1, left monitor, focused: `h_tiles(1 *4 v_tiles(7 2))`, floating 12, and 11 of the hidden app
    - workspace 2, right monitor: `h_tiles(5 v_accordion(9 10))`
    - workspaces 3 and 4, invisible (parked): `h_tiles(3 6)`, `h_tiles(8)`

    Apps: terminal 1 2 3, browser 4 5 6, editor 7 8, chat 9 10, music 11 (hidden), finder 12.
    Each scenario starts from this world after two heavy refreshes.
    """

private func setUpRealisticWorld() {
    world.config.enableNormalizationFlattenContainers = true // The defaults
    world.config.enableNormalizationOppositeOrientationForNestedContainers = true
    fake.monitorInfos = [testMonitor, rightTestMonitor]
    fake.apps = [terminal, browser, editor, chat, music, finder]
    fake.hiddenApps = [music.pid]
    updateMonitors()
    let one = Workspace.get(byName: "1")
    let two = Workspace.get(byName: "2")
    check(testMonitor.setActiveWorkspace(one) && rightTestMonitor.setActiveWorkspace(two))

    let left = Rect(topLeftX: 100, topLeftY: 100, width: 800, height: 600)
    let right = Rect(topLeftX: 2020, topLeftY: 100, width: 800, height: 600)
    let root1 = one.rootTilingContainerCreatingIfNeeded()
    openRegistered(1, terminal, root1, left)
    openRegistered(4, browser, root1, left)
    let column = TilingContainer(parent: root1, weight: 1, .v, .tiles)
    openRegistered(7, editor, column, left)
    openRegistered(2, terminal, column, left)
    openRegistered(11, music, root1, left) // The first heavy refresh moves it to macos_hidden
    openRegistered(12, finder, one.containerCreatingIfNeeded(.floating), Rect(topLeftX: 300, topLeftY: 300, width: 600, height: 400))
    let root2 = two.rootTilingContainerCreatingIfNeeded()
    openRegistered(5, browser, root2, right)
    let accordion = TilingContainer(parent: root2, weight: 1, .v, .accordion)
    openRegistered(9, chat, accordion, right)
    openRegistered(10, chat, accordion, right)
    let root3 = Workspace.get(byName: "3").rootTilingContainerCreatingIfNeeded()
    openRegistered(3, terminal, root3, left)
    openRegistered(6, browser, root3, left)
    openRegistered(8, editor, Workspace.get(byName: "4").rootTilingContainerCreatingIfNeeded(), left)

    check(testWindow(4).focusWindow())
    fake.focused = 4
    Workspace.garbageCollectUnusedWorkspaces()
    axAppWindows = Set(fake.windows.keys)
}

/// A window that macOS shows and AeroSpace has registered
private func openRegistered(_ id: WindowId, _ app: AppInfo, _ parent: Container, _ rect: Rect) {
    fake.windows[id] = FakeWindow(app: app, rect: rect, title: "Window \(id)")
    _ = Window(id: id, app, parent: parent, weight: 1, index: nil)
}

// MARK: The scenarios

private struct Scenario {
    let name: String
    let run: @MainActor () async throws -> [Phase]
}

private let idleScenario = "Heavy refresh, nothing changed, twice"

private let allScenarios: [Scenario] = [
    Scenario(name: "The first two heavy refreshes of the world") {
        [try await heavy("1st"), try await heavy("2nd", isIdle: true)]
    },
    Scenario(name: idleScenario) {
        try await settled { [try await heavy("1st", isIdle: true), try await heavy("2nd", isIdle: true)] }
    },
    Scenario(name: "Light session, nothing changed") {
        try await settled { try await session("light session, empty body", isIdle: true) {} }
    },
    Scenario(name: "Focus follows mouse, nothing changed") {
        try await settled {
            [try await measure("ffm light session", isIdle: true) { try await world.sessions.light(.focusFollowsMouse, .forceRun) {} }]
        }
    },
    Scenario(name: "`workspace 2` (visible on the right monitor)") { try await settled { try await command("workspace 2") } },
    Scenario(name: "`workspace 3` (invisible)") { try await settled { try await command("workspace 3") } },
    Scenario(name: "`focus right` (same workspace)") { try await settled { try await command("focus right") } },
    Scenario(name: "`focus --window-id 6` (invisible workspace 3)") { try await settled { try await command("focus --window-id 6") } },
    Scenario(name: "`move left` (within its container)") { try await settled { try await command("move left") } },
    Scenario(name: "`move-node-to-workspace 3`") { try await settled { try await command("move-node-to-workspace 3") } },
    Scenario(name: "`resize smart +50`") { try await settled { try await command("resize smart +50") } },
    Scenario(name: "`layout floating tiling`, twice") {
        try await settled {
            let toFloating: [Phase] = try await command("layout floating tiling")
            return toFloating + (try await command("layout floating tiling"))
        }
    },
    Scenario(name: "Open window 13 (browser), focused") {
        try await settled {
            fake.windows[13] = FakeWindow(app: browser, rect: Rect(topLeftX: 200, topLeftY: 150, width: 1000, height: 700), title: "Window 13")
            fake.focused = 13
            return [try await heavy("heavy refresh (AX windowCreated)"), try await heavy("heavy refresh (AX moved/resized)")]
        }
    },
    Scenario(name: "A minimized window of unknown kind appears (13, browser)") {
        try await settled {
            let window = FakeWindow(app: browser, rect: Rect(topLeftX: 200, topLeftY: 150, width: 1000, height: 700), title: "Window 13")
            window.kind = nil // Off-screen, with a kind that depends on its level: AeroSpace doesn't register it
            window.level = nil
            window.isMinimized = true
            fake.windows[13] = window
            return [try await heavy("heavy refresh (AX windowCreated)"), try await heavy("next heavy refresh", isIdle: true)]
        }
    },
    Scenario(name: "Close focused window 4 (macOS focuses 5)") {
        try await settled {
            fake.windows[4] = nil
            fake.focused = 5
            return [try await heavy("heavy refresh (AX destroyed)"), try await heavy("heavy refresh (AX moved/resized)")]
        }
    },
    Scenario(name: "Unplug the right monitor, plug it back") {
        try await settled {
            unplugRightMonitor()
            let unplugged: [Phase] = [try await heavy("unplugged: heavy refresh"), try await heavy("unplugged: next heavy refresh")]
            fake.monitorInfos = [testMonitor, rightTestMonitor]
            return unplugged + [try await heavy("plugged: heavy refresh"), try await heavy("plugged: next heavy refresh")]
        }
    },
    Scenario(name: "Hide the editor (cmd-h), unhide it") {
        try await settled {
            fake.hiddenApps.insert(editor.pid)
            let hidden: Phase = try await measure("didHide light session") {
                try await world.sessions.onAppHidden()
                world.sessions.cancelHeavy() // Measured as the next phase
            }
            let next: Phase = try await heavy("its heavy refresh")
            fake.hiddenApps.remove(editor.pid)
            return [hidden, next, try await heavy("didUnhide heavy refresh"), try await heavy("heavy refresh (AX moved/resized)")]
        }
    },
    Scenario(name: "Hide the editor with automatically-unhide-macos-hidden-apps") {
        try await settled {
            world.config.automaticallyUnhideMacosHiddenApps = true
            fake.hiddenApps.insert(editor.pid)
            let hidden: Phase = try await measure("didHide light session") {
                try await world.sessions.onAppHidden()
                world.sessions.cancelHeavy()
            }
            return [hidden]
        }
    },
]

/// macOS moves the windows of the right monitor to the left one
private func unplugRightMonitor() {
    let width = rightTestMonitor.rect.width
    for window in fake.windows.values {
        guard let rect = window.rect, rect.topLeftX >= rightTestMonitor.rect.topLeftX else { continue }
        window.rect = Rect(topLeftX: rect.topLeftX - width, topLeftY: rect.topLeftY, width: rect.width, height: rect.height)
    }
    fake.monitorInfos = [testMonitor]
}

/// The world after two heavy refreshes
private func settled(_ body: () async throws -> [Phase]) async throws -> [Phase] {
    await Reconcile.heavy(.ax("settle"))
    await Reconcile.heavy(.ax("settle"))
    return try await body()
}

/// After a scenario: the world settles, then the apps move and resize every tile and move every parked window behind
/// AeroSpace's back. The next heavy refresh reads where they are, so it puts each one back
private func convergence() async -> Convergence {
    await Reconcile.heavy(.ax("settle"))
    await Reconcile.heavy(.ax("settle"))
    var expected: [WindowId: Rect] = [:]
    for window in world.windows.values {
        let isTile = window.parent is TilingContainer && !fake.isParked(window.windowId)
        guard isTile || fake.isParked(window.windowId), let fakeWindow = fake.windows[window.windowId], let rect = fakeWindow.rect
        else { continue }
        expected[window.windowId] = rect
        fakeWindow.rect = Rect(topLeftX: rect.topLeftX + 37, topLeftY: rect.topLeftY + 37, width: rect.width - (isTile ? 50 : 0), height: rect.height)
    }
    await Reconcile.heavy(.ax("moved behind AeroSpace's back"))
    return Convergence(moved: expected.count, notBack: expected.keys.filter { fake.windows[$0]?.rect != expected[$0] }.sorted())
}

private struct Convergence {
    let moved: Int
    let notBack: [WindowId]
}

/// A hotkey that runs `command`
private func command(_ command: String) async throws -> [Phase] {
    try await session("`\(command)` light session") {
        let output = await runCmd(command)
        expectEqual(output.exitCode, 0, "\(command): \(output.stderr)")
    }
}

/// A light session, then the heavy refresh that it schedules
private func session(_ name: String, isIdle: Bool = false, _ body: () async throws -> ()) async throws -> [Phase] {
    let light = try await measure(name, isIdle: isIdle) {
        try await world.sessions.light(.hotkeyBinding, .forceRun, body: body)
        world.sessions.cancelHeavy() // Measured as the next phase
    }
    return [light, try await heavy("its heavy refresh", isIdle: isIdle)]
}

private func heavy(_ name: String, isIdle: Bool = false) async throws -> Phase {
    try await measure(name, isIdle: isIdle) { await Reconcile.heavy(.ax(name)) }
}

private func measure(_ name: String, isIdle: Bool = false, _ body: () async throws -> ()) async throws -> Phase {
    let before = MacosState()
    var listings: [Listing] = []
    fake.onRead = { call in
        if call == .listWindows { listings.append(Listing()) }
    }
    fake.resetCalls()
    try await body()
    fake.onRead = nil
    return Phase(name: name, isIdle: isIdle, calls: fake.calls, before: before, after: MacosState(), listings: listings)
}

// MARK: The measurement

/// What macOS shows before or after a phase
private struct MacosState {
    let rects: [WindowId: Rect] = fake.windows.compactMapValues(\.rect)
    let parked: Set<WindowId> = Set(fake.windows.keys.filter { fake.isParked($0) })
    let focused: WindowId? = fake.focused
    let hiddenApps: Set<pid_t> = fake.hiddenApps
    let appOf: [WindowId: pid_t] = fake.windows.mapValues(\.app.pid)
}

/// The windows that LivePlatform's AxApp has registered (observed): the world's, then each one that a listing returns,
/// whether AeroSpace registers it or not
private var axAppWindows: Set<WindowId> = []

/// What one `listWindows` listed: the windows of each app that answered, and those that AxApp registers now
private struct Listing {
    let windowsPerApp: [[WindowId]]
    let new: Set<WindowId>

    init() {
        windowsPerApp = fake.apps.compactMap { app in
            fake.answers[app.pid] == false ? nil : fake.windows.filter { $0.value.app == app }.keys.sorted()
        }
        new = Set(windowsPerApp.flatMap(\.self)).subtracting(axAppWindows)
        axAppWindows.formUnion(new)
    }
}

private struct Phase {
    let name: String
    /// Expected to move, park and focus nothing
    let isIdle: Bool
    let calls: [PlatformCall]
    let before: MacosState
    let after: MacosState
    let listings: [Listing]

    /// The AX calls that LivePlatform makes for the log. From LivePlatform.swift, AxApp.swift, Placement.swift, and the
    /// getters of accessibility.swift (`windowsAttr` and `focusedWindowAttr` call `_AXUIElementGetWindow` per element)
    /// and AxUiElementWindowType.swift (`getWindowType` of a standard window: the close button, the subrole twice, the
    /// fullscreen button and whether it's enabled)
    var cost: AxCost {
        var cost = AxCost()
        var listings = listings.makeIterator()
        var appsWithPlacementWrites: Set<pid_t> = []
        for (index, call) in calls.enumerated() {
            switch call {
                case .listWindows:
                    let listing = listings.next()
                    for ids in listing?.windowsPerApp ?? [] {
                        cost.appReads += 1 // AXWindows
                        for id in ids {
                            // _AXUIElementGetWindow. New to AxApp: 5 AXObserverAddNotification and its size (registerWindow)
                            cost.read(id, listing?.new.contains(id) == true ? 7 : 1)
                        }
                    }
                case .focusedWindow: cost.appReads += 2 // AXFocusedWindow, _AXUIElementGetWindow
                case .classify(let ids): for id in ids { cost.read(id, 5 + 1) } // getWindowType, then the position and size
                case .nativeFacts(let ids): for id in ids { cost.read(id, 1) } // AXUIElementCopyMultipleAttributeValues
                case .observedRect(let id), .rect(let id): cost.read(id, 1) // The position and size in one call
                case .title(let id), .facts(let id), .debugInfo(let id): cost.read(id, 1) // debugInfo: more, unused here
                case .kind(let id): cost.read(id, 5)
                case .windowCount(let pid): cost.appReads += 1 + after.appOf.values.count { $0 == pid }
                case .floating, .park, .leave, .rememberFloatingSize, .restoreFloatingSize: break // See .axRead and .frame
                case .axRead(let id): cost.read(id, 1) // The position and size in one call
                case .frame(let id, let topLeft, let size):
                    cost.write(id, axWrites(topLeft: topLeft, size: size))
                    if index > 0, calls[index - 1] == .restoreFloatingSize(id) {
                        cost.appReads += 1 // Its own job reads AXEnhancedUserInterface
                    } else if let pid = before.appOf[id] ?? after.appOf[id] {
                        appsWithPlacementWrites.insert(pid)
                    }
                case .focus(let id):
                    cost.write(id, 2) // Two monitors with separate Spaces: AXMain, AXRaise (#101)
                    cost.appXpc += 1 // Then NSRunningApplication.activate
                case .close(let id):
                    cost.read(id, 1) // The close button
                    cost.write(id, 1) // AXPress
                case .setNative(let id, _): cost.write(id, 1)
                case .unhideApp, .quit: cost.appXpc += 1
            }
        }
        cost.appReads += appsWithPlacementWrites.count // One AXEnhancedUserInterface read per app job that writes
        return cost
    }

    var waste: Waste {
        var waste = Waste()
        var frameWrites: [WindowId: Int] = [:]
        for case .frame(let id, let topLeft, let size) in calls {
            frameWrites[id, default: 0] += axWrites(topLeft: topLeft, size: size)
        }
        let written = Set(frameWrites.keys)
        for (id, writes) in frameWrites where before.rects[id] != nil && before.rects[id] == after.rects[id] {
            waste.sameFrame[id] = writes
        }
        for case .axRead(let id) in calls where !written.contains(id) {
            waste.checkReads += 1
        }
        var focused = before.focused
        var hiddenApps = before.hiddenApps
        var reads: [String: Int] = [:]
        for call in calls {
            switch call {
                case .focus(let id):
                    if focused == id { waste.focusOfFocused += 1 }
                    focused = id
                case .unhideApp(let pid):
                    if !hiddenApps.contains(pid) { waste.unhideOfVisible += 1 }
                    hiddenApps.remove(pid)
                default: break
            }
            for key in call.readKeys { reads[key, default: 0] += 1 }
        }
        waste.repeatedReads = reads.filter { $0.value > 1 }.map { "\($0.key)×\($0.value)" }.sorted()
        return waste
    }
}

/// The AX writes of `AxPlacementWindow.setFrame`: the size, the position, the size again (#143, #335)
private func axWrites(topLeft: CGPoint?, size: CGSize?) -> Int {
    switch (topLeft, size) {
        case (nil, nil): 0
        case (nil, _?), (_?, nil): 1
        case (_?, _?): 3
    }
}

/// The AX calls of a phase, see ``Phase/cost``
private struct AxCost {
    var reads: [WindowId: Int] = [:]
    var writes: [WindowId: Int] = [:]
    /// The reads of no single window: each app's AXWindows, the focused window, AXEnhancedUserInterface
    var appReads = 0
    /// launchservicesd XPCs of NSRunningApplication (activate, unhide, terminate), not AX
    var appXpc = 0

    var totalReads: Int { reads.values.reduce(appReads, +) }
    var totalWrites: Int { writes.values.reduce(0, +) }

    mutating func read(_ id: WindowId, _ count: Int) { reads[id, default: 0] += count }
    mutating func write(_ id: WindowId, _ count: Int) { writes[id, default: 0] += count }
}

/// The calls of a phase that leave macOS as it was
private struct Waste {
    /// The AX writes of each window whose frame writes left it where it was
    var sameFrame: [WindowId: Int] = [:]
    /// The AX reads of the windows that the phase didn't write: a tile at its frame, a parked window still in its corner, a
    /// floating window still on its monitor
    var checkReads = 0
    /// Native focus of the window that macOS focuses already
    var focusOfFocused = 0
    var unhideOfVisible = 0
    /// The reads that the phase made more than once, but the placements' own, e.g. `facts(4)×2`
    var repeatedReads: [String] = []
}

extension PlatformCall {
    /// AeroSpace's effects on macOS: a frame write, a focus, ...
    fileprivate var isEffect: Bool {
        switch self {
            case .frame, .focus, .close, .setNative, .unhideApp, .quit, .restoreFloatingSize: true
            default: false
        }
    }

    /// What the call reads, per window or app, to spot repeated reads
    fileprivate var readKeys: [String] {
        switch self {
            case .listWindows: ["listWindows"]
            case .focusedWindow: ["focusedWindow"]
            case .classify(let ids): ids.flatMap { ["kind(\($0))", "rect(\($0))"] }
            case .nativeFacts(let ids): ids.map { "facts(\($0))" }
            case .facts(let id): ["facts(\(id))"]
            case .observedRect(let id), .rect(let id): ["rect(\(id))"]
            case .kind(let id): ["kind(\(id))"]
            case .title(let id): ["title(\(id))"]
            case .debugInfo(let id): ["debugInfo(\(id))"]
            case .windowCount(let pid): ["windowCount(\(pid))"]
            default: []
        }
    }
}

// MARK: The table

private func axCallTable(_ results: [(scenario: String, phases: [Phase], convergence: Convergence)]) -> String {
    var lines: [String] = [
        "# AX calls per scenario (FakePlatform)",
        "",
        "Generated by `AX_CALL_TABLE=<file> swift test --skip-build --filter AxCallCountTest`.",
        "",
        worldDescription,
        "",
        "Columns: `Fake calls` is the length of FakePlatform's log. `AX reads` and `AX writes` estimate the AX calls that",
        "LivePlatform makes for it (AxCallCountTest.swift, `Phase.cost`): a frame write with a position and a size is 3",
        "writes, a native focus is 2 (AXMain, AXRaise) plus an activation. `XPC`: NSRunningApplication calls (activate,",
        "unhide), not AX. `Same-frame writes`: the AX writes of the windows whose writes left them where they were",
        "(`writes/windows`). `Check reads`: the reads of the windows that the phase didn't write (tiles at their frame,",
        "parked windows in their corner, floating windows on their monitor). `repeated`: reads made more than once in the",
        "phase.",
        "",
        "| Scenario | Phase | Fake calls | AX reads | AX writes | XPC | Same-frame writes | Check reads | Other waste |",
        "|---|---|---:|---:|---:|---:|---:|---:|---|",
    ]
    for (scenario, phases, _) in results {
        for (index, phase) in phases.enumerated() {
            let cost = phase.cost
            let waste = phase.waste
            let sameFrame = waste.sameFrame.values.reduce(0, +)
            var other: [String] = []
            if waste.focusOfFocused > 0 { other.append("focus of the focused window ×\(waste.focusOfFocused)") }
            if waste.unhideOfVisible > 0 { other.append("unhide of a visible app ×\(waste.unhideOfVisible)") }
            if !waste.repeatedReads.isEmpty { other.append("repeated: " + waste.repeatedReads.joined(separator: " ")) }
            let cells: [String] = [
                index == 0 ? scenario : "",
                phase.name,
                "\(phase.calls.count)",
                "\(cost.totalReads)",
                "\(cost.totalWrites)",
                "\(cost.appXpc)",
                sameFrame == 0 ? "0" : "\(sameFrame)/\(waste.sameFrame.count)",
                "\(waste.checkReads)",
                other.joined(separator: "; "),
            ]
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
    }
    lines += [
        "",
        "## Convergence",
        "",
        "After each scenario, the world settles (two heavy refreshes). Then the apps move every tile by (37, 37) and make it",
        "50 pt narrower, and move every parked window by (37, 37), behind AeroSpace's back. The next heavy refresh must put",
        "each one back.",
        "",
        "| Scenario | Windows moved | Not back after one heavy refresh |",
        "|---|---:|---|",
    ]
    for (scenario, _, convergence) in results {
        let notBack = convergence.notBack.isEmpty ? "none" : convergence.notBack.map(\.description).joined(separator: ", ")
        lines.append("| \(scenario) | \(convergence.moved) | \(notBack) |")
    }
    lines += [
        "",
        "## Per window",
        "",
        "Each cell is `reads/writes` of one window; `=` marks writes that left the window where it was, `p` a window",
        "that is parked after the phase. `app` is the reads of no single window. `Calls` is the fake's log by kind.",
    ]
    let ids: [WindowId] = (1 ... 13).map { WindowId(raw: $0) }
    for (scenario, phases, _) in results {
        lines += ["", "### \(scenario)", ""]
        lines.append("| Phase | app | " + ids.map(\.description).joined(separator: " | ") + " | Calls |")
        lines.append("|---|---:|" + String(repeating: "---:|", count: ids.count) + "---|")
        for phase in phases {
            let cost = phase.cost
            let waste = phase.waste
            let cells: [String] = ids.map { id in
                let (reads, writes) = (cost.reads[id] ?? 0, cost.writes[id] ?? 0)
                let parked = phase.after.parked.contains(id) ? "p" : ""
                if reads == 0 && writes == 0 { return parked }
                return "\(reads)/\(writes)" + (waste.sameFrame[id] != nil ? "=" : "") + parked
            }
            lines.append("| \(phase.name) | \(cost.appReads) | " + cells.joined(separator: " | ") + " | \(phase.callSummary) |")
        }
    }
    return lines.joined(separator: "\n") + "\n"
}

extension Phase {
    /// The log by kind, in the order of first appearance, e.g. `focusedWindow, listWindows, nativeFacts(11), frame×9`
    fileprivate var callSummary: String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for call in calls {
            let key: String = switch call {
                case .classify(let ids): "classify(\(ids.count))"
                case .nativeFacts(let ids): "nativeFacts(\(ids.count))"
                case .focus(let id): "focus(\(id))"
                default: "\(call.kind)"
            }
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        return order.map { key in counts[key] == 1 ? key : "\(key)×\(counts[key] ?? 0)" }.joined(separator: ", ")
    }
}
