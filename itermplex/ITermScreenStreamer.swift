import Foundation
import AppKit

enum RemoteMessage: Equatable {
    case resize(cols: Int, rows: Int)
    case data(String)
    /// The session ended or can no longer be streamed; the client should stop.
    case ended
}

/// Owns the `iterm_streamer.py` daemon and turns its NDJSON frames into
/// `RemoteMessage`s. Streaming is per connection: several connections may view
/// the same session (e.g. a page reload, or two devices), each with its own VT
/// state, and the daemon streams a session as long as any connection wants it.
/// All failures are silent: like `ITermMonitor`, this is an enhancement and
/// must never disrupt the app.
final class ITermScreenStreamer: @unchecked Sendable {
    private let pythonEnvironment: PythonEnvironment
    private let iTermBundleId = "com.googlecode.iterm2"

    /// One viewer of one session. Each has its own synthesizer so its VT diff
    /// state is independent of other viewers of the same session.
    private struct Connection {
        let session: String
        let synthesizer: VTSynthesizer
        let sink: @Sendable (RemoteMessage) -> Void
    }

    private let lock = NSLock()
    // Serializes writes to the daemon's stdin so a large `input` command split
    // across multiple pipe writes cannot interleave with another command.
    private let stdinQueue = DispatchQueue(label: "eu.kloosterman.itermplex.streamer.stdin")
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readHandle: FileHandle?
    private var stopped = false
    private var launching = false
    private var buffer = Data()

    private var connections: [UUID: Connection] = [:]
    // Last decoded frame per streaming session, replayed to a connection that
    // attaches after streaming has already begun so it paints immediately.
    private var lastFrame: [String: ScreenFrame] = [:]

    init(pythonEnvironment: PythonEnvironment = PythonEnvironment()) {
        self.pythonEnvironment = pythonEnvironment
    }

    /// Pure transform: renders a decoded frame through a synthesizer into the
    /// ordered messages (a `.resize` when dimensions change, then the `.data`
    /// VT chunk).
    static func messages(for frame: ScreenFrame, synthesizer: VTSynthesizer) -> [RemoteMessage] {
        let output = synthesizer.render(frame)
        var messages: [RemoteMessage] = []
        if let resize = output.resize { messages.append(.resize(cols: resize.cols, rows: resize.rows)) }
        messages.append(.data(output.vt))
        return messages
    }

    /// Convenience over `messages(for frame:synthesizer:)` that decodes a line
    /// first; returns no messages for a non-frame or malformed line.
    static func messages(for line: String, synthesizer: VTSynthesizer) -> [RemoteMessage] {
        guard let frame = ScreenFrame.decode(line: line) else { return [] }
        return messages(for: frame, synthesizer: synthesizer)
    }

    /// Begins streaming `session` to `onMessage` and returns a token to pass to
    /// `detach`. The sink must only enqueue (it is invoked while the internal
    /// lock is held, so it must not call back into the streamer).
    @discardableResult
    func attach(session: String, onMessage: @escaping @Sendable (RemoteMessage) -> Void) -> UUID {
        let id = UUID()
        let synthesizer = VTSynthesizer()
        lock.lock()
        stopped = false
        let alreadyStreaming = connections.values.contains { $0.session == session }
        connections[id] = Connection(session: session, synthesizer: synthesizer, sink: onMessage)
        if alreadyStreaming, let frame = lastFrame[session] {
            // The daemon only emits on the next change, so paint the current
            // screen into the new connection now (rendered under the lock so it
            // is ordered before any later frame for this connection).
            for message in Self.messages(for: frame, synthesizer: synthesizer) { onMessage(message) }
        }
        lock.unlock()
        launchIfNeeded()
        if !alreadyStreaming { writeCommand(["cmd": "attach", "session": session]) }
        return id
    }

    func detach(connectionId: UUID) {
        lock.lock()
        guard let connection = connections.removeValue(forKey: connectionId) else {
            lock.unlock()
            return
        }
        let session = connection.session
        let sessionGone = !connections.values.contains { $0.session == session }
        if sessionGone { lastFrame[session] = nil }
        let idle = connections.isEmpty
        lock.unlock()
        if sessionGone { writeCommand(["cmd": "detach", "session": session]) }
        if idle { stop() }
    }

    func send(session: String, text: String) {
        writeCommand(["cmd": "input", "session": session, "text": text])
    }

    /// Launches the daemon at most once: only when no process is live and no
    /// launch is already in flight. This guards against concurrent `attach`
    /// calls (or a relaunch racing a live process) spawning duplicate daemons.
    private func launchIfNeeded() {
        lock.lock()
        guard process == nil, !launching, !stopped, !connections.isEmpty else {
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

    func stop() {
        lock.lock()
        stopped = true
        launching = false
        connections = [:]
        lastFrame = [:]
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
        guard let handle else { return }
        var line = data
        line.append(0x0A)
        stdinQueue.async { try? handle.write(contentsOf: line) }
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
        // not cleared it, so each relaunch also releases the previous process's
        // fd (mirrors ITermMonitor's stale-handle handling).
        let staleHandle = self.readHandle
        self.process = process
        self.stdinHandle = inPipe.fileHandleForWriting
        self.readHandle = outPipe.fileHandleForReading
        self.buffer = Data()
        launching = false
        // A relaunched daemon restreams from a full screen, so reset each
        // synthesizer to force a full redraw rather than diffing against stale
        // rows, then re-attach every session that still has viewers.
        for connection in connections.values { connection.synthesizer.reset() }
        let sessions = Set(connections.values.map { $0.session })
        lock.unlock()
        staleHandle?.readabilityHandler = nil
        for session in sessions { writeCommand(["cmd": "attach", "session": session]) }
    }

    /// Clears the current process's state when it exits, then relaunches if
    /// connections remain. Ignores a stale handler firing for a process that
    /// has already been replaced.
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
            if let session = ScreenFrame.detachedSession(line: line) {
                // The session ended; tell every viewer of it and evict them.
                lock.lock()
                let ended = connections.filter { $0.value.session == session }
                for id in ended.keys { connections.removeValue(forKey: id) }
                lastFrame[session] = nil
                for connection in ended.values { connection.sink(.ended) }
                lock.unlock()
                continue
            }
            guard let frame = ScreenFrame.decode(line: line) else { continue }
            // Render and deliver under the lock so each connection's frames are
            // yielded to its sink in emission order (the sinks only enqueue).
            lock.lock()
            lastFrame[frame.session] = frame
            for connection in connections.values where connection.session == frame.session {
                for message in Self.messages(for: frame, synthesizer: connection.synthesizer) {
                    connection.sink(message)
                }
            }
            lock.unlock()
        }
    }

    private func scheduleRelaunch() {
        lock.lock()
        let done = stopped || connections.isEmpty
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
