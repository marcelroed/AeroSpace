import AppKit
import Common

@MainActor
var appForTests: (any AbstractApp)? = nil

@MainActor
func getNativeFocusedWindow(_ cm: CancellationMode) async throws -> Window? {
    if isUnitTest { return try await appForTests?.getFocusedWindow(cm) }
    check(appForTests == nil)
    guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else { return nil }
    return try await MacApp.getOrRegister(frontmostApplication)?.getFocusedWindow(cm)
}
