import Foundation

/// Watches a workspace folder for changes to its contents (including creating,
/// modifying, or deleting `itermplex.json`) using a DispatchSource on the
/// directory file descriptor. Calls `onChange` on the main queue.
final class ConfigWatcher {
    private let folder: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var scoped = false

    init(folder: URL, onChange: @escaping () -> Void) {
        self.folder = folder
        self.onChange = onChange
    }

    func start() {
        stop()
        scoped = folder.startAccessingSecurityScopedResource()
        descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            if scoped { folder.stopAccessingSecurityScopedResource(); scoped = false }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        src.setEventHandler { [weak self] in self?.onChange() }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.descriptor >= 0 { close(self.descriptor); self.descriptor = -1 }
            if self.scoped { self.folder.stopAccessingSecurityScopedResource(); self.scoped = false }
        }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}
