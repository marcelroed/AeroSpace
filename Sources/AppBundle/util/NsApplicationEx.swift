import AppKit

extension NSApplication.ActivationPolicy {
    nonisolated var prettyDescription: String {
        switch self {
            case .accessory: "accessory"
            case .prohibited: "prohibited"
            case .regular: "regular"
            @unknown default: "unknown \(self.rawValue)"
        }
    }
}
