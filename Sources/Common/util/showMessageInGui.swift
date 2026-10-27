import Foundation

// todo refactor. showMessageInGui in common code looks weird
func showMessageInGui(filenameIfConsoleApp: String, title: String, message: String) {
    let titleAndMessage = "##### \(title) #####\n\n" + message
    if isCli {
        print(titleAndMessage)
    } else {
        // Per-user directory: a directory in the shared /tmp may belong to another user.
        // Don't die if writing fails: dieT calls this function, dying here would recurse forever
        let cachesDir = FileManager.default.temporaryDirectory.appending(component: "bobko.aerospace")
        let file = cachesDir.appending(component: filenameIfConsoleApp)
        do {
            try FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
            try (titleAndMessage + "\n").write(to: file, atomically: true, encoding: .utf8)
        } catch {
            eprint("Can't write \(file.path): \(error)")
            return
        }

        file.absoluteURL.open(with: URL(filePath: "/System/Applications/Utilities/Console.app"))
    }
}
