import Foundation
import AppKit

protocol SessionMonitoring: Sendable {
    func start(onEvent: @escaping @MainActor (MonitorEvent) -> Void)
    func stop()
}

/// Owns the lifecycle of the `iterm_monitor.py` daemon and forwards its
/// events. All failures are silent: the monitor is an enhancement and must
/// never disrupt core terminal actions.
final class ITermMonitor: SessionMonitoring, @unchecked Sendable {
    private let pythonEnvironment: PythonEnvironment
    private let iTermBundleId = "com.googlecode.iterm2"

    private let lock = NSLock()
    private var process: Process?
    private var readHandle: FileHandle?
    private var onEvent: (@MainActor (MonitorEvent) -> Void)?
    private var stopped = false
    private var buffer = Data()

    init(pythonEnvironment: PythonEnvironment = PythonEnvironment()) {
        self.pythonEnvironment = pythonEnvironment
    }

    func start(onEvent: @escaping @MainActor (MonitorEvent) -> Void) {
        lock.lock()
        self.onEvent = onEvent
        self.stopped = false
        lock.unlock()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.stop() }
        // ensureInterpreter() can shell out to `python -m venv` / `pip install` on first
        // use, which is slow; keep that off the caller's (often main) thread.
        DispatchQueue.global().async { [weak self] in self?.launch() }
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        teardown(terminate: true)
    }

    /// Clears the readability handler and drops the process/handle references
    /// under the lock, then (optionally) terminates the process outside the
    /// lock to avoid reentrancy. Foundation only tears down the GCD dispatch
    /// source backing `readabilityHandler` when it is explicitly set to nil,
    /// so this must run on every teardown path (explicit stop, or the
    /// process's own termination) to avoid leaking a file descriptor.
    private func teardown(terminate: Bool) {
        lock.lock()
        let running = process
        let handle = readHandle
        process = nil
        readHandle = nil
        lock.unlock()

        handle?.readabilityHandler = nil
        if terminate {
            running?.terminate()
        }
    }

    private func launch() {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: iTermBundleId) != nil,
              let python = try? pythonEnvironment.ensureInterpreter(),
              let script = Bundle.main.url(forResource: "iterm_monitor", withExtension: "py"),
              let cookie = requestCookie() else {
            return  // silently inactive
        }

        let process = Process()
        process.executableURL = python
        process.arguments = [script.path]
        var environment = ProcessInfo.processInfo.environment
        environment["ITERM2_COOKIE"] = cookie
        process.environment = environment

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        process.terminationHandler = { [weak self] _ in
            self?.teardown(terminate: false)
            self?.scheduleRelaunch()
        }

        do {
            try process.run()
        } catch {
            return  // silently inactive
        }

        let readHandle = outPipe.fileHandleForReading
        lock.lock()
        if stopped {
            // stop() ran while process.run() was in flight; the process was
            // never published, so stop() couldn't terminate it. Do that now
            // rather than leaving an orphaned daemon behind.
            lock.unlock()
            readHandle.readabilityHandler = nil
            process.terminate()
            return
        }
        self.process = process
        self.readHandle = readHandle
        self.buffer = Data()
        lock.unlock()
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
        }
        let handler = onEvent
        lock.unlock()

        guard let handler else { return }
        let events = lines.compactMap { MonitorEvent.decode(line: $0) }
        guard !events.isEmpty else { return }
        // Deliver as one batch so events decoded from the same read (e.g.
        // title then terminated for one session) stay in order; separate
        // Tasks give no such guarantee.
        Task { @MainActor in
            for event in events {
                handler(event)
            }
        }
    }

    private func scheduleRelaunch() {
        lock.lock()
        let done = stopped
        lock.unlock()
        guard !done else { return }
        // Backoff before relaunch so a persistently failing daemon does not spin.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stillWanted = !self.stopped
            self.lock.unlock()
            if stillWanted { self.launch() }
        }
    }

    private func requestCookie() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"iTerm2\" to request cookie"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let cookie = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus == 0 && !cookie.isEmpty) ? cookie : nil
    }
}
