#!/usr/bin/env python3
"""Bridge between itermplex and iTerm2's Python API.

Subcommands (each prints one line of JSON to stdout on success):
  open FOLDER [--window WINDOW_ID]  -> {"session_id": ..., "window_id": ...}
  focus SESSION_ID                  -> {"found": true|false}
  close SESSION_ID                  -> {"closed": true|false}
"""
import sys
import json
import shlex
import argparse
import iterm2


async def _open(connection, folder, window_id, command):
    app = await iterm2.async_get_app(connection)
    window = app.get_window_by_id(window_id) if window_id else None
    if window is not None:
        tab = await window.async_create_tab()
        session = tab.current_session
    else:
        window = await iterm2.Window.async_create(connection)
        session = window.current_tab.current_session
    await session.async_send_text("cd " + shlex.quote(folder) + "\n")
    if command:
        await session.async_send_text(command + "\n")
    return {"session_id": session.session_id, "window_id": window.window_id}


async def _focus(connection, session_id):
    app = await iterm2.async_get_app(connection)
    session = app.get_session_by_id(session_id)
    if session is None:
        return {"found": False}
    await session.async_activate(True, True)
    return {"found": True}


async def _close(connection, session_id):
    app = await iterm2.async_get_app(connection)
    session = app.get_session_by_id(session_id)
    if session is None:
        return {"closed": False}
    await session.async_close()
    return {"closed": True}


def main():
    parser = argparse.ArgumentParser(description="itermplex iTerm2 bridge")
    sub = parser.add_subparsers(dest="subcommand", required=True)
    p_open = sub.add_parser("open")
    p_open.add_argument("folder")
    p_open.add_argument("--window", dest="window", default=None)
    p_open.add_argument("--command", dest="command", default=None)
    p_focus = sub.add_parser("focus")
    p_focus.add_argument("session_id")
    p_close = sub.add_parser("close")
    p_close.add_argument("session_id")
    args = parser.parse_args()

    holder = {}

    async def run(connection):
        if args.subcommand == "open":
            holder["value"] = await _open(connection, args.folder, args.window, args.command)
        elif args.subcommand == "focus":
            holder["value"] = await _focus(connection, args.session_id)
        elif args.subcommand == "close":
            holder["value"] = await _close(connection, args.session_id)

    try:
        iterm2.run_until_complete(run, retry=False)
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(str(exc))
        sys.exit(2)

    print(json.dumps(holder["value"]))


if __name__ == "__main__":
    main()
