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
        launch()
    }

    func stop() {
        lock.lock()
        stopped = true
        let running = process
        process = nil
        lock.unlock()
        running?.terminate()
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
            self?.scheduleRelaunch()
        }

        do {
            try process.run()
        } catch {
            return  // silently inactive
        }
        lock.lock()
        self.process = process
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
        for line in lines {
            guard let event = MonitorEvent.decode(line: line) else { continue }
            Task { @MainActor in handler(event) }
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
