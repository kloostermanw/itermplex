#!/usr/bin/env python3
"""Persistent iTerm2 monitor for itermplex.

Given ITERM2_COOKIE in the environment, connects to iTerm2 and streams
per-session events as one compact JSON object per line to stdout:
  {"type": "title",      "session_id": S, "name": N}
  {"type": "bell",       "session_id": S}
  {"type": "job",        "session_id": S, "job_name": J}
  {"type": "terminated", "session_id": S}
Reads only session variables, never screen contents. Runs until killed.
"""
import sys
import json
import asyncio
import iterm2


def _emit(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


async def _watch_title(connection, session_id):
    async with iterm2.VariableMonitor(
        connection, iterm2.VariableScopes.SESSION, "name", session_id
    ) as mon:
        while True:
            name = await mon.async_get()
            if name:  # skip empty/None titles
                _emit({"type": "title", "session_id": session_id, "name": name})


async def _watch_job(connection, session_id):
    # jobName is None at a bare shell (no shell integration) and a non-empty
    # string (e.g. claude's version) while an agent runs. Coerce None -> ""
    # and always emit, so the app can tell "shell/idle" ("") from "running".
    async with iterm2.VariableMonitor(
        connection, iterm2.VariableScopes.SESSION, "jobName", session_id
    ) as mon:
        while True:
            job = await mon.async_get()
            _emit({"type": "job", "session_id": session_id, "job_name": job or ""})


async def _watch_bell(connection, session_id):
    # VariableMonitor fires the current value on attach; that baseline is not
    # a new bell. Emit only on subsequent increments.
    async with iterm2.VariableMonitor(
        connection, iterm2.VariableScopes.SESSION, "bellCount", session_id
    ) as mon:
        first = True
        while True:
            await mon.async_get()
            if first:
                first = False
                continue
            _emit({"type": "bell", "session_id": session_id})


async def _watch_session(connection, session_id):
    await asyncio.gather(
        _watch_title(connection, session_id),
        _watch_job(connection, session_id),
        _watch_bell(connection, session_id),
    )


async def _watch_terminations(connection):
    async with iterm2.SessionTerminationMonitor(connection) as mon:
        while True:
            session_id = await mon.async_get()
            _emit({"type": "terminated", "session_id": session_id})


async def main(connection):
    app = await iterm2.async_get_app(connection)
    asyncio.create_task(_watch_terminations(connection))
    async with iterm2.EachSessionOnceMonitor(app) as mon:
        while True:
            session_id = await mon.async_get()
            asyncio.create_task(_watch_session(connection, session_id))


iterm2.run_forever(main)
