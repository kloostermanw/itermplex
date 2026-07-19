import Foundation
import AppKit

enum RemoteMessage: Equatable {
    case resize(cols: Int, rows: Int)
    case data(String)
}

/// Owns the `iterm_streamer.py` daemon and turns its NDJSON frames into
/// `RemoteMessage`s per attached session. All failures are silent: like
/// `ITermMonitor`, this is an enhancement and must never disrupt the app.
final class ITermScreenStreamer: @unchecked Sendable {
    private let pythonEnvironment: PythonEnvironment
    private let iTermBundleId = "com.googlecode.iterm2"

    private let lock = NSLock()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readHandle: FileHandle?
    private var stopped = false
    private var launching = false
    private var buffer = Data()

    // Per attached session: its synthesizer (frame state) and message sink.
    private var synthesizers: [String: VTSynthesizer] = [:]
    private var sinks: [String: @Sendable (RemoteMessage) -> Void] = [:]

    init(pythonEnvironment: PythonEnvironment = PythonEnvironment()) {
        self.pythonEnvironment = pythonEnvironment
    }

    /// Pure transform used by tests and by `consume`: decodes a frame line and
    /// produces the ordered messages (a `.resize` when dimensions change, then
    /// the `.data` VT chunk).
    static func messages(for line: String, synthesizer: VTSynthesizer) -> [RemoteMessage] {
        guard let frame = ScreenFrame.decode(line: line) else { return [] }
        let output = synthesizer.render(frame)
        var messages: [RemoteMessage] = []
        if let resize = output.resize { messages.append(.resize(cols: resize.cols, rows: resize.rows)) }
        messages.append(.data(output.vt))
        return messages
    }

    func attach(session: String, onMessage: @escaping @Sendable (RemoteMessage) -> Void) {
        lock.lock()
        stopped = false
        synthesizers[session] = VTSynthesizer()
        sinks[session] = onMessage
        lock.unlock()
        launchIfNeeded()
        writeCommand(["cmd": "attach", "session": session])
    }

    /// Launches the daemon at most once: only when no process is live and no
    /// launch is already in flight. This guards against concurrent `attach`
    /// calls (or a relaunch racing a live process) spawning duplicate daemons.
    private func launchIfNeeded() {
        lock.lock()
        guard process == nil, !launching, !stopped, !sinks.isEmpty else {
            lock.unlock()
            return
        }
        launching = true
        lock.unlock()
        DispatchQueue.global().async { [weak self] in self?.launch() }
    }

    private func clearLaunching() {
        lock.lock()
        launching = false
        lock.unlock()
    }

    func detach(session: String) {
        writeCommand(["cmd": "detach", "session": session])
        lock.lock()
        synthesizers[session] = nil
        sinks[session] = nil
        let idle = sinks.isEmpty
        lock.unlock()
        if idle { stop() }
    }

    func send(session: String, text: String) {
        writeCommand(["cmd": "input", "session": session, "text": text])
    }

    func stop() {
        lock.lock()
        stopped = true
        launching = false
        let running = process
        let handle = readHandle
        process = nil
        readHandle = nil
        stdinHandle = nil
        lock.unlock()
        handle?.readabilityHandler = nil
        running?.terminate()
    }

    private func writeCommand(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        lock.lock()
        let handle = stdinHandle
        lock.unlock()
        var line = data
        line.append(0x0A)
        try? handle?.write(contentsOf: line)
    }

    private func launch() {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: iTermBundleId) != nil,
              let python = try? pythonEnvironment.ensureInterpreter(),
              let script = Bundle.main.url(forResource: "iterm_streamer", withExtension: "py"),
              let cookie = requestCookie() else {
            clearLaunching()
            return  // silently inactive
        }
        let process = Process()
        process.executableURL = python
        process.arguments = [script.path]
        var environment = ProcessInfo.processInfo.environment
        environment["ITERM2_COOKIE"] = cookie
        process.environment = environment

        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        process.terminationHandler = { [weak self] proc in self?.handleTermination(of: proc) }

        do { try process.run() } catch { clearLaunching(); return }

        lock.lock()
        if stopped {
            launching = false
            lock.unlock()
            outPipe.fileHandleForReading.readabilityHandler = nil
            process.terminate()
            return
        }
        // Retire any handle from a prior process whose terminationHandler had
        // not cleared it, so each new publish also releases the old fd
        // (mirrors ITermMonitor's stale-handle handling).
        let staleHandle = self.readHandle
        self.process = process
        self.stdinHandle = inPipe.fileHandleForWriting
        self.readHandle = outPipe.fileHandleForReading
        self.buffer = Data()
        launching = false
        // Re-attach any sessions requested before the process was ready.
        let sessions = Array(sinks.keys)
        lock.unlock()
        staleHandle?.readabilityHandler = nil
        for session in sessions { writeCommand(["cmd": "attach", "session": session]) }
    }

    /// Clears the current process's state when it exits, then relaunches if
    /// sessions are still attached. Ignores a stale handler firing for a
    /// process that has already been replaced.
    private func handleTermination(of proc: Process) {
        lock.lock()
        guard process === proc else { lock.unlock(); return }
        readHandle?.readabilityHandler = nil
        process = nil
        stdinHandle = nil
        readHandle = nil
        lock.unlock()
        scheduleRelaunch()
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8) { lines.append(line) }
        }
        lock.unlock()

        for line in lines {
            guard let session = ScreenFrame.decode(line: line)?.session else { continue }
            lock.lock()
            let synth = synthesizers[session]
            let sink = sinks[session]
            lock.unlock()
            guard let synth, let sink else { continue }
            for message in Self.messages(for: line, synthesizer: synth) { sink(message) }
        }
    }

    private func scheduleRelaunch() {
        lock.lock()
        let done = stopped || sinks.isEmpty
        lock.unlock()
        guard !done else { return }
        // Backoff before relaunch so a persistently failing daemon does not
        // spin. `launchIfNeeded` no-ops if a process is already live or another
        // launch is in flight.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.launchIfNeeded()
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
