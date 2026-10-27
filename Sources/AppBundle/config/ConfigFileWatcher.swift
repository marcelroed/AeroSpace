import Common
import Foundation

private struct ConfigFileWatcher: ~Copyable {
    private let source: DispatchSourceFileSystemObject
    private let fd: Int32

    init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        fd = unsafe open(url.path, O_EVTONLY)
        if fd < 0 { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .main,
        )
        source.setEventHandler { onChange() } // On the main queue, so the closure is main actor isolated
        source.setCancelHandler { [fd] in close(fd) }
        source.activate()
    }

    deinit {
        source.cancel()
    }
}

// periphery:ignore - assign-only: the value keeps the watcher alive
private var currentWatcher: ConfigFileWatcher? = nil
private var debounceTask: Task<Void, any Error>? = nil

private let debounceDelay: Duration = .milliseconds(200)

func syncConfigFileWatcher() {
    currentWatcher = nil
    if !config.autoReloadConfig { return }
    currentWatcher = ConfigFileWatcher(url: configUrl) {
        debounceTask?.cancel()
        debounceTask = Task.startUnstructured {
            try await Task.sleep(for: debounceDelay)
            if let token: RunSessionGuard = .isServerEnabled {
                try await runLightSession(.configAutoReload, token) {
                    _ = await reloadConfig_nonCancellable()
                }
            }
        }
    }
}
