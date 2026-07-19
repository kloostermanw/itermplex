#!/usr/bin/env python3
"""Persistent iTerm2 screen streamer for itermplex.

Given ITERM2_COOKIE in the environment, connects to iTerm2 and, for each
attached session, streams the styled visible screen grid as one compact JSON
object per line to stdout. Reads commands (attach/detach/input) as one JSON
object per line on stdin. Runs until killed.
"""
import sys
import json
import asyncio
import iterm2

# Strong references to in-flight tasks. asyncio.create_task() only stores a
# weak reference on the event loop, so without this the GC can collect a
# still-running task and silently kill its streaming (see iterm_monitor.py).
_tasks = set()
_attached = {}          # session_id -> asyncio.Task


def _spawn(coro):
    task = asyncio.create_task(coro)
    _tasks.add(task)
    task.add_done_callback(_tasks.discard)
    return task


def _emit(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def _palette_index(color):
    """Map a CellStyle.Color to -1 (default/alternate) or a 0..255 palette index."""
    if color is None or (not color.is_rgb and not color.is_standard):
        return -1
    if color.is_standard:
        return color.standard
    rgb = color.rgb

    # Approximate 24-bit RGB into the 6x6x6 color cube (indices 16..231).
    def q(v):
        return 0 if v < 48 else 1 if v < 115 else (v - 35) // 40

    return 16 + 36 * q(rgb.red) + 6 * q(rgb.green) + q(rgb.blue)


def _frame_for(session_id, contents):
    rows = contents.number_of_lines
    lines = []
    cols = 0
    for y in range(rows):
        line = contents.line(y)
        text = line.string
        cols = max(cols, len(text))
        cells = []
        for x in range(len(text)):
            ch = line.string_at(x) or " "
            style = line.style_at(x)
            if style is None:
                cells.append([ch, -1, -1, 0])
            else:
                cells.append([ch, _palette_index(style.fg_color),
                              _palette_index(style.bg_color), 1 if style.bold else 0])
        lines.append(cells)
    cursor = contents.cursor_coord
    return {"type": "frame", "session": session_id,
            "cols": max(cols, 1), "rows": rows,
            "cursor": {"x": cursor.x, "y": cursor.y}, "lines": lines}


async def _stream(connection, session_id):
    app = await iterm2.async_get_app(connection)
    session = app.get_session_by_id(session_id)
    if session is None:
        _emit({"type": "detached", "session": session_id, "reason": "no such session"})
        return
    try:
        async with session.get_screen_streamer() as streamer:
            while True:
                contents = await streamer.async_get(style=True)
                if contents is not None:
                    _emit(_frame_for(session_id, contents))
    except asyncio.CancelledError:
        raise
    except Exception as exc:  # noqa: BLE001
        _emit({"type": "detached", "session": session_id, "reason": repr(exc)})
    finally:
        _attached.pop(session_id, None)


async def _send_input(connection, session_id, text):
    app = await iterm2.async_get_app(connection)
    session = app.get_session_by_id(session_id)
    if session is not None:
        await session.async_send_text(text)


def _handle_command(connection, line):
    try:
        cmd = json.loads(line)
    except ValueError:
        return
    name = cmd.get("cmd")
    session_id = cmd.get("session")
    if name == "attach" and session_id and session_id not in _attached:
        _attached[session_id] = _spawn(_stream(connection, session_id))
    elif name == "detach" and session_id:
        task = _attached.pop(session_id, None)
        if task is not None:
            task.cancel()
    elif name == "input" and session_id:
        _spawn(_send_input(connection, session_id, cmd.get("text", "")))


async def _read_stdin(connection):
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader()
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    while True:
        raw = await reader.readline()
        if not raw:            # stdin closed: parent gone, exit.
            for task in list(_attached.values()):
                task.cancel()
            return
        _handle_command(connection, raw.decode("utf-8", "replace").strip())


async def main(connection):
    await _read_stdin(connection)


iterm2.run_forever(main)
