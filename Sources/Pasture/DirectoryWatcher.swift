import Foundation

/// Builds a resumed DispatchSource for a directory file descriptor. Module-level
/// free function to keep GCD closures out of actor isolation (Swift 6).
private func makeWatchSource(fd: Int32, onEvent: @escaping @Sendable () -> Void) -> any DispatchSourceFileSystemObject {
    let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd,
        eventMask: .write,
        queue: .global(qos: .utility)
    )
    source.setEventHandler(handler: onEvent)
    source.setCancelHandler {
        close(fd)
    }
    source.resume()
    return source
}

/// Watches the library root and its collection subdirectories, debouncing change
/// bursts into a single `onChange` callback on the main actor. Encapsulates all
/// GCD-managed watcher state (`nonisolated(unsafe)`) behind a single responsibility
/// so `MDFileManager` stays free of file-watching concerns.
@MainActor
final class DirectoryWatcher {
    var onChange: (() -> Void)?

    private let debounceInterval: TimeInterval
    nonisolated(unsafe) private var rootSource: (any DispatchSourceFileSystemObject)?
    nonisolated(unsafe) private var subdirectorySources: [String: any DispatchSourceFileSystemObject] = [:]
    nonisolated(unsafe) private var reloadWorkItem: DispatchWorkItem?

    init(debounceInterval: TimeInterval = 0.5) {
        self.debounceInterval = debounceInterval
    }

    deinit {
        reloadWorkItem?.cancel()
        rootSource?.cancel()
        for source in subdirectorySources.values {
            source.cancel()
        }
    }

    /// Starts watching the library root. Idempotent.
    func watchRoot(_ url: URL) {
        guard rootSource == nil else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        rootSource = makeWatchSource(fd: fd, onEvent: eventHandler())
    }

    /// Reconciles subdirectory watchers with the current collection names.
    func updateSubdirectories(names: [String], under root: URL) {
        let current = Set(names)
        let watched = Set(subdirectorySources.keys)

        for name in watched.subtracting(current) {
            subdirectorySources[name]?.cancel()
            subdirectorySources.removeValue(forKey: name)
        }

        for name in current.subtracting(watched) {
            let subdirURL = root.appendingPathComponent(name)
            let fd = open(subdirURL.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            subdirectorySources[name] = makeWatchSource(fd: fd, onEvent: eventHandler())
        }
    }

    func stop() {
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        rootSource?.cancel()
        rootSource = nil
        for source in subdirectorySources.values {
            source.cancel()
        }
        subdirectorySources.removeAll()
    }

    /// GCD event → hop to main → debounce → onChange.
    private func eventHandler() -> @Sendable () -> Void {
        { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.scheduleChange()
                }
            }
        }
    }

    private func scheduleChange() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }
}
