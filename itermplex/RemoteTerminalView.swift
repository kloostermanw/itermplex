import SwiftUI
import SwiftTerm

/// Hosts a SwiftTerm `TerminalView` (AppKit) wired to a `RemoteTerminalConnection`
/// for one remote session: incoming VT bytes feed the terminal, incoming resizes
/// resize the terminal model, and keystrokes typed into the terminal are
/// forwarded upstream. The connection starts in `makeNSView` and is torn down in
/// `dismantleNSView`, so removing this view from the hierarchy (closing its tab)
/// cancels the socket and leaves no running receive task behind.
struct RemoteTerminalView: NSViewRepresentable {
    let remoteConnection: RemoteConnection
    let sessionId: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TerminalView {
        let terminalView = TerminalView(frame: .zero)
        terminalView.terminalDelegate = context.coordinator

        let connection = RemoteTerminalConnection(connection: remoteConnection, sessionId: sessionId)
        connection.onData = { [weak terminalView] bytes in
            terminalView?.feed(byteArray: bytes[...])
        }
        connection.onResize = { [weak terminalView] cols, rows in
            terminalView?.resize(cols: cols, rows: rows)
        }
        connection.onEnded = { [weak terminalView] in
            terminalView?.feed(text: "\r\n\u{1B}[31m[session ended]\u{1B}[0m\r\n")
        }
        context.coordinator.connection = connection
        connection.start()

        return terminalView
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        // remoteConnection/sessionId are fixed for the lifetime of this view;
        // RemoteTerminalTabsView keys each tab's view by its RemoteTerminalTabID,
        // so a changed session gets a fresh view (and coordinator) rather than
        // an update here.
    }

    static func dismantleNSView(_ nsView: TerminalView, coordinator: Coordinator) {
        coordinator.connection?.stop()
        coordinator.connection = nil
        nsView.terminalDelegate = nil
    }

    /// Forwards the terminal's outgoing keystrokes to the connection. The other
    /// `TerminalViewDelegate` requirements have no remote equivalent here (no
    /// window to resize, no title bar, no host-reported directory to surface),
    /// so they're no-ops.
    @MainActor
    final class Coordinator: NSObject, @MainActor TerminalViewDelegate {
        var connection: RemoteTerminalConnection?

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            connection?.send(data)
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
