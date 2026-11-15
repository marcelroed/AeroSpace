import AppKit
import Common
import MachO
import Synchronization

/// A macOS Space: a Mission Control desktop, or a fullscreen app's Space (SkyLight's `id64`)
nonisolated struct SpaceId: Hashable, Sendable, CustomStringConvertible {
    let raw: UInt64
    var description: String { raw.description }
}

/// The desktops as one read of the window server saw them, see ``MacosSpaces/snapshot()``
nonisolated struct SpacesSnapshot: Sendable {
    /// The active desktop, where the windows of the shown workspaces belong. nil while a fullscreen app's Space is active
    let shown: SpaceId?
    /// The desktop that the windows of the invisible workspaces park on: the last desktop but the active one. nil if
    /// there's none, or while a fullscreen app's Space is active
    let parking: SpaceId?
    /// Every desktop, in Mission Control's order
    let desktops: [SpaceId]
}

/// The Spaces of a placement batch, see ``PlacementState/apply(_:to:trustsLastSeen:spaces:)``
nonisolated struct BatchSpaces: Sendable {
    /// The active desktop: a window that the batch shows, or parks in a corner, moves there if it's on another Space. nil:
    /// the batch moves no window back
    let shown: SpaceId?
    /// The desktop that the batch's parks of ``ParkTarget/onMacosSpace`` move their windows to. nil: they park in a corner
    let parking: SpaceId?
    /// The windows that the window server showed on the parking desktop when the batch was made: mostly the parked ones.
    /// But after the user switched to that desktop (or macOS did, to activate an app whose window was parked there), the
    /// parking desktop is the other one, where the windows of the shown workspaces still are
    let onParkingSpace: Set<WindowId>

    static let none = BatchSpaces(shown: nil, parking: nil, onParkingSpace: [])
}

/// A window that was sent to a Space, see ``MacosSpaces/waitUntilMoved(_:until:)``
nonisolated struct SpaceMove {
    let windowId: UInt32
    let space: SpaceId
    /// false once a newer write of the window is posted or termination started: nobody waits for this move then
    let isCurrent: () -> Bool
}

/// The macOS Spaces through SkyLight, the private framework under CoreGraphics, for `experimental-park-on-macos-space`.
/// It's looked up at runtime, as ``windowServerParents(_:)``: if a macOS update drops a symbol, ``shared`` is nil, and the
/// windows park in a corner.
///
/// Since macOS 14.5, the window server ignores an unprivileged process that moves another app's window to another Space
/// (`SLSMoveWindowsToManagedSpace`). macOS 26.4 added `SLSBridgedMoveWindowsToManagedSpaceOperation`, which it performs
/// for any process: yabai 7.1.25 uses it, and it works on macOS 27.3. Its performer isn't exported (a static C++
/// function), so it's found in SkyLight's symbol table. A move is asynchronous: the window server moves the window ~2 ms
/// later (~20 ms for the process's first move). A window on another Space isn't composited, its app sees it occluded
/// (and may stop rendering it), and AX keeps answering about it, but the app's AXWindows no longer lists it
@safe nonisolated final class MacosSpaces: @unchecked Sendable {
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias CopyWindowsWithOptionsAndTags = @convention(c) (
        Int32, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>,
    ) -> Unmanaged<CFArray>?
    /// `-[SLSBridgedMoveWindowsToManagedSpaceOperation initWithWindows:spaceID:]`: consumes `self`, returns retained
    private typealias InitMoveOperation = @convention(c) (Unmanaged<AnyObject>, Selector, NSArray, UInt64) -> Unmanaged<AnyObject>?
    /// `SLSPerformAsynchronousBridgedWindowManagementOperation(SLSAsynchronousBridgedWindowManagementOperation *)`. What
    /// it leaves in the return register is garbage: the window server performs the operation later
    private typealias PerformOperation = @convention(c) (UnsafeMutableRawPointer) -> Void

    private let connection: Int32
    private let copyManagedDisplaySpaces: CopyManagedDisplaySpaces
    private let copySpacesForWindows: CopySpacesForWindows
    private let copyWindowsWithOptionsAndTags: CopyWindowsWithOptionsAndTags
    private let moveOperationClass: AnyClass
    private let initMoveOperation: InitMoveOperation
    private let initMoveOperationSelector: Selector
    private let performOperation: PerformOperation
    /// The windows that a park moved to another desktop and nothing moved back since: termination moves them back
    private let parkedWindows: Mutex<Set<UInt32>> = Mutex([])

    /// nil if a symbol is missing (e.g. before macOS 26.4). The symbol table is read once, on first use
    static let shared: MacosSpaces? = MacosSpaces()

    /// Set by the first move: from then on, the batches read the Spaces even if the config turned the parking off, so
    /// that the parked windows come back, and termination brings them back. Static: reading it doesn't load ``shared``
    static var hasMovedWindows: Bool { didMoveWindows.load(ordering: .relaxed) }
    private static let didMoveWindows: Atomic<Bool> = Atomic(false)

    private init?() {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
        guard let handle = unsafe dlopen(path, RTLD_LAZY) else { return nil }
        func symbol<T>(_ name: String, _: T.Type) -> T? {
            unsafe dlsym(handle, name).map { unsafe unsafeBitCast($0, to: T.self) }
        }
        let initSelector = NSSelectorFromString("initWithWindows:spaceID:")
        guard let mainConnectionId = symbol("SLSMainConnectionID", (@convention(c) () -> Int32).self),
              let copyManagedDisplaySpaces = unsafe symbol("SLSCopyManagedDisplaySpaces", CopyManagedDisplaySpaces.self),
              let copySpacesForWindows = unsafe symbol("SLSCopySpacesForWindows", CopySpacesForWindows.self),
              let copyWindowsWithOptionsAndTags = unsafe symbol("SLSCopyWindowsWithOptionsAndTags", CopyWindowsWithOptionsAndTags.self),
              let moveOperationClass = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation"),
              let initImplementation = unsafe class_getMethodImplementation(moveOperationClass, initSelector),
              let perform = unsafe localSymbol(
                  "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation",
                  inImage: path,
              )
        else { return nil }
        connection = mainConnectionId()
        unsafe self.copyManagedDisplaySpaces = copyManagedDisplaySpaces
        unsafe self.copySpacesForWindows = copySpacesForWindows
        unsafe self.copyWindowsWithOptionsAndTags = copyWindowsWithOptionsAndTags
        self.moveOperationClass = moveOperationClass
        unsafe initMoveOperation = unsafe unsafeBitCast(initImplementation, to: InitMoveOperation.self)
        initMoveOperationSelector = initSelector
        unsafe performOperation = unsafe unsafeBitCast(perform, to: PerformOperation.self)
    }

    /// The desktops (~0.13 ms). nil if each display has its own Spaces (`Displays have separate Spaces`) with more than
    /// one display: the parking supports one set of Spaces only
    func snapshot() -> SpacesSnapshot? {
        guard let displays = unsafe copyManagedDisplaySpaces(connection)?.takeRetainedValue() as? [NSDictionary],
              displays.count == 1,
              let current = (displays[0]["Current Space"] as? NSDictionary).flatMap(spaceId),
              let spaces = displays[0]["Spaces"] as? [NSDictionary]
        else { return nil }
        // Type 0 is a desktop, 4 a fullscreen app's Space
        let desktops = spaces.filter { ($0["type"] as? NSNumber)?.intValue == 0 }.compactMap(spaceId)
        let isOnDesktop = desktops.contains(current)
        return SpacesSnapshot(
            shown: isOnDesktop ? current : nil,
            parking: isOnDesktop ? desktops.last { $0 != current } : nil,
            desktops: desktops,
        )
    }

    /// The windows on the Space, of every app, also the desktop's own (~0.1 ms)
    func windows(on space: SpaceId) -> [UInt32] {
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        let spaces = [NSNumber(value: space.raw)] as CFArray
        // Options 0x2: the windows on the Space, the minimized ones excluded (yabai's `space_window_list`)
        guard let windows = unsafe copyWindowsWithOptionsAndTags(connection, 0, spaces, 0x2, &setTags, &clearTags)?.takeRetainedValue()
        else { return [] }
        return (windows as? [NSNumber] ?? []).map(\.uint32Value)
    }

    /// The Space of the window (~0.06 ms). nil if it's gone, or on more than one (a window on every Space)
    func space(of windowId: UInt32) -> SpaceId? {
        let windows = [NSNumber(value: windowId)] as CFArray
        // Mask 0x7: every kind of Space
        guard let spaces = unsafe copySpacesForWindows(connection, 0x7, windows)?.takeRetainedValue() as? [NSNumber],
              spaces.count == 1
        else { return nil }
        return SpaceId(raw: spaces[0].uint64Value)
    }

    /// Asks the window server to move the windows to the Space. It does ~2 ms later. Any thread. `parks`: the move hides
    /// the windows, so termination moves them back; otherwise it shows them. Nothing moves in `--read-only` mode
    func move(_ windowIds: [UInt32], to space: SpaceId, parks: Bool) {
        if windowIds.isEmpty || serverArgs.isReadOnly { return }
        Self.didMoveWindows.store(true, ordering: .relaxed)
        parkedWindows.withLock { parked in
            if parks { parked.formUnion(windowIds) } else { parked.subtract(windowIds) }
        }
        // alloc + init, with init's ownership: it consumes the instance and returns a retained one
        guard let instance = class_createInstance(moveOperationClass, 0),
              let operation = unsafe initMoveOperation(
                  Unmanaged.passRetained(instance as AnyObject),
                  initMoveOperationSelector,
                  windowIds.map { NSNumber(value: $0) } as NSArray,
                  space.raw,
              )?.takeRetainedValue()
        else { return }
        withExtendedLifetime(operation) {
            unsafe performOperation(Unmanaged.passUnretained(operation).toOpaque())
        }
    }

    /// Termination: moves the parked windows back to the active desktop (the first one while a fullscreen app's Space is
    /// active), and waits until they are there, at most `timeout`. Any thread: it never waits for the main thread
    func bringBackParkedWindows(timeout: DispatchTimeInterval) {
        let parked = parkedWindows.withLock { Array($0) }
        guard !parked.isEmpty, let snapshot = snapshot(), let target = snapshot.shown ?? snapshot.desktops.first else { return }
        move(parked, to: target, parks: false)
        waitUntilMoved(parked.map { SpaceMove(windowId: $0, space: target, isCurrent: { true }) }, until: .now() + timeout)
    }

    /// The window is on the parking desktop, where a park moved it: the window server still has it, so it's alive. AX
    /// doesn't list it there, and the refresh would ask its app otherwise (see ``AxApp/refreshWindows(isLockScreen:_:)``)
    func isParked(_ windowId: UInt32) -> Bool {
        parkedWindows.withLock { $0.contains(windowId) } && space(of: windowId) != nil
    }

    /// Waits until the window server shows each moved window on its Space, or until `deadline`. A window that is gone, or
    /// whose move isn't current, isn't waited for. The windows that it timed out for
    @discardableResult
    func waitUntilMoved(_ moves: [SpaceMove], until deadline: DispatchTime) -> [UInt32] {
        var pending = moves
        while true {
            pending.removeAll { move in
                guard move.isCurrent(), let space = space(of: move.windowId) else { return true }
                return space == move.space
            }
            if pending.isEmpty || DispatchTime.now() >= deadline { return pending.map(\.windowId) }
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    private func spaceId(_ space: NSDictionary) -> SpaceId? {
        (space["id64"] as? NSNumber).map { SpaceId(raw: $0.uint64Value) }
    }
}

/// At startup: the windows that a killed AeroSpace left on the parking desktop come back to the active one (a quit or a
/// crash brings them back, see ``MacosSpaces/bringBackParkedWindows(timeout:)``). AX lists the windows of the active
/// Space only, so the first refresh wouldn't find them. Only the windows of regular apps at the normal level move: the
/// desktop's own windows (e.g. its wallpaper) stay
func bringBackWindowsOfLastRun() async {
    guard config.experimentalParkOnMacosSpace, let spaces = MacosSpaces.shared, let snapshot = spaces.snapshot(),
          let shown = snapshot.shown, let parking = snapshot.parking
    else { return }
    let ids = Set(spaces.windows(on: parking))
    // Not CGWindowListCreateDescriptionFromArray: it takes an array of raw window ids, which Swift can't make safely
    guard !ids.isEmpty, let infos = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [NSDictionary] else { return }
    let appWindows: [UInt32] = infos.compactMap { info in
        guard let id = (info[kCGWindowNumber] as? NSNumber)?.uint32Value, ids.contains(id),
              (info[kCGWindowLayer] as? NSNumber)?.intValue == 0,
              let pid = (info[kCGWindowOwnerPID] as? NSNumber)?.int32Value,
              NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
        else { return nil }
        return id
    }
    if appWindows.isEmpty { return }
    spaces.move(appWindows, to: shown, parks: false)
    let deadline = DispatchTime.now() + .milliseconds(500)
    while appWindows.contains(where: { spaces.space(of: $0) == parking }) && DispatchTime.now() < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// The address of a symbol that dlsym doesn't find (a local one, e.g. a static C++ function) in a loaded image, from the
/// image's symbol table. In the dyld shared cache, the image's `__LINKEDIT` is the cache's, at the same slide
nonisolated private func localSymbol(_ name: String, inImage path: String) -> UnsafeMutableRawPointer? {
    for index in 0 ..< _dyld_image_count() {
        guard let imageName = unsafe _dyld_get_image_name(index), unsafe String(cString: imageName) == path,
              let header = unsafe _dyld_get_image_header(index)
        else { continue }
        let slide = _dyld_get_image_vmaddr_slide(index)
        var linkedit: segment_command_64? = nil
        var symtab: symtab_command? = nil
        var command = unsafe UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        let commandCount = unsafe header.pointee.ncmds
        for _ in 0 ..< commandCount {
            let load = unsafe command.loadUnaligned(as: load_command.self)
            if load.cmd == UInt32(LC_SEGMENT_64) {
                let segment = unsafe command.loadUnaligned(as: segment_command_64.self)
                let name = withUnsafeBytes(of: segment.segname) { unsafe String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                if name == SEG_LINKEDIT { linkedit = segment }
            } else if load.cmd == UInt32(LC_SYMTAB) {
                symtab = unsafe command.loadUnaligned(as: symtab_command.self)
            }
            unsafe command = command.advanced(by: Int(load.cmdsize))
        }
        guard let linkedit, let symtab else { return nil }
        let base = Int(linkedit.vmaddr) - Int(linkedit.fileoff) + slide
        guard let strings = unsafe UnsafeRawPointer(bitPattern: base + Int(symtab.stroff))?.assumingMemoryBound(to: CChar.self),
              let symbols = unsafe UnsafeRawPointer(bitPattern: base + Int(symtab.symoff))?.assumingMemoryBound(to: nlist_64.self)
        else { return nil }
        return name.withCString { target in
            for symbolIndex in 0 ..< Int(symtab.nsyms) {
                let symbol = unsafe symbols[symbolIndex]
                if unsafe strcmp(strings + Int(symbol.n_un.n_strx), target) == 0 {
                    return unsafe UnsafeMutableRawPointer(bitPattern: Int(symbol.n_value) + slide)
                }
            }
            return nil
        }
    }
    return nil
}
