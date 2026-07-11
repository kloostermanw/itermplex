#!/usr/bin/env python3
"""Bridge between itermplex and iTerm2's Python API.

Subcommands (each prints one line of JSON to stdout on success):
  open FOLDER [--window WINDOW_ID] [--command CMD] [--badge TEXT]  -> {"session_id": ..., "window_id": ...}
  focus SESSION_ID                  -> {"found": ..., "job_name": ...}
  send SESSION_ID --text TEXT       -> {"sent": true|false}
  close SESSION_ID                  -> {"closed": true|false}
  contents SESSION_ID [--lines N]   -> {"found": ..., "output": ...}
"""
import sys
import json
import base64
import shlex
import argparse
import iterm2


async def _set_badge(session, text):
    # iTerm2 badge format is a base64-encoded string set via OSC 1337. We inject
    # it as program output (not typed at the prompt) so it never touches the
    # command line. See https://iterm2.com/documentation-badges.html.
    encoded = base64.b64encode(text.encode("utf-8")).decode("ascii")
    await session.async_inject(b"\033]1337;SetBadgeFormat=" + encoded.encode("ascii") + b"\a")


async def _open(connection, folder, window_id, command, badge):
    app = await iterm2.async_get_app(connection)
    window = app.get_window_by_id(window_id) if window_id else None
    if window is not None:
        tab = await window.async_create_tab()
        session = tab.current_session
    else:
        window = await iterm2.Window.async_create(connection)
        session = window.current_tab.current_session
    if badge:
        await _set_badge(session, badge)
    await session.async_send_text("cd " + shlex.quote(folder) + "\n")
    if command:
        await session.async_send_text(command + "\n")
    return {"session_id": session.session_id, "window_id": window.window_id}


async def _focus(connection, session_id):
    app = await iterm2.async_get_app(connection)
    session = app.get_session_by_id(session_id)
    if session is None:
        return {"found": False, "job_name": None}
    job_name = await session.async_get_variable("jobName")
    await session.async_activate(True, True)
    return {"found": True, "job_name": job_name}


async def _send(connection, session_id, text):
    app = await iterm2.async_get_app(connection)
    session = app.get_session_by_id(session_id)
    if session is None:
        return {"sent": False}
    await session.async_send_text(text)
    return {"sent": True}


async def _close(connection, session_id):
    app = await iterm2.async_get_app(connection)
    session = app.get_session_by_id(session_id)
    if session is None:
        return {"closed": False}
    await session.async_close()
    return {"closed": True}


async def _contents(connection, session_id, lines):
    app = await iterm2.async_get_app(connection)
    session = app.get_session_by_id(session_id)
    if session is None:
        return {"found": False, "output": ""}
    # Read the whole visible grid. Content sits at the top with blank padding
    # below, so we trim trailing blank rows first, then keep the last `lines`.
    contents = await session.async_get_screen_contents()
    rows = [contents.line(i).string.rstrip() for i in range(contents.number_of_lines)]
    while rows and rows[-1] == "":
        rows.pop()
    if lines > 0:
        rows = rows[-lines:]
    return {"found": True, "output": "\n".join(rows)}


def main():
    parser = argparse.ArgumentParser(description="itermplex iTerm2 bridge")
    sub = parser.add_subparsers(dest="subcommand", required=True)
    p_open = sub.add_parser("open")
    p_open.add_argument("folder")
    p_open.add_argument("--window", dest="window", default=None)
    p_open.add_argument("--command", dest="command", default=None)
    p_open.add_argument("--badge", dest="badge", default=None)
    p_focus = sub.add_parser("focus")
    p_focus.add_argument("session_id")
    p_send = sub.add_parser("send")
    p_send.add_argument("session_id")
    p_send.add_argument("--text", dest="text", required=True)
    p_close = sub.add_parser("close")
    p_close.add_argument("session_id")
    p_contents = sub.add_parser("contents")
    p_contents.add_argument("session_id")
    p_contents.add_argument("--lines", dest="lines", type=int, default=50)
    args = parser.parse_args()

    holder = {}

    async def run(connection):
        if args.subcommand == "open":
            holder["value"] = await _open(connection, args.folder, args.window, args.command, args.badge)
        elif args.subcommand == "focus":
            holder["value"] = await _focus(connection, args.session_id)
        elif args.subcommand == "send":
            holder["value"] = await _send(connection, args.session_id, args.text)
        elif args.subcommand == "close":
            holder["value"] = await _close(connection, args.session_id)
        elif args.subcommand == "contents":
            holder["value"] = await _contents(connection, args.session_id, args.lines)

    try:
        iterm2.run_until_complete(run, retry=False)
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(str(exc))
        sys.exit(2)

    print(json.dumps(holder["value"]))


if __name__ == "__main__":
    main()
