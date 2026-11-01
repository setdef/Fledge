# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Delivery of a terminal UI built with Fledge, on macOS and Linux.

Runs the built app's program in a pseudo-terminal of 80 by 24 cells, as a
person runs it in a terminal, with a PATH that holds no Ruby and a Ruby's
settings in the environment that the app must not see, waits for the
app's first screen, types a key and sees the screen change, types Ctrl-C
and expects the app to restore the terminal and exit with status 0.

    python3 -I deliver-tui.py PROGRAM
"""
import fcntl
import os
import pty
import re
import select
import struct
import sys
import tempfile
import termios
import time

CONTROL = re.compile(rb"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07")


def fail(message, seen):
    print(f"::error::Delivery (terminal UI): {message}")
    print(repr(seen[-2000:]))
    sys.exit(1)


program = os.path.abspath(sys.argv[1])
home = tempfile.mkdtemp()
empty = tempfile.mkdtemp()
env = {
    "PATH": empty,
    "HOME": home,
    "TERM": "xterm-256color",
    "LANG": "en_US.UTF-8" if sys.platform == "darwin" else "C.UTF-8",
    "RUBYOPT": "-rnonexistent_library_a_person_set",
    "RUBYLIB": home,
    "GEM_HOME": os.path.join(home, "gems"),
}
pid, fd = pty.fork()
if pid == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    os.chdir("/")
    os.execve(program, [program], env)

seen = b""


def read_until(test, seconds):
    global seen
    deadline = time.time() + seconds
    while time.time() < deadline:
        if test(CONTROL.sub(b"", seen)):
            return True
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            try:
                data = os.read(fd, 65536)
            except OSError:
                return test(CONTROL.sub(b"", seen))
            if not data:
                return test(CONTROL.sub(b"", seen))
            seen += data
    return False


if not read_until(lambda text: re.search(rb"Current\s*count:\s*0\.", text), 60):
    fail("the app never showed its first screen, 'Current count: 0.'", seen)
print("ok: the first screen shows 'Current count: 0.'")
if b"\x1b[?1049h" not in seen:
    fail("the app did not enter the alternate screen", seen)

mark = len(seen)
os.write(fd, b"a")
if not read_until(lambda text: re.search(rb"(?<![0-9])1(?![0-9])", CONTROL.sub(b"", seen[mark:])), 30):
    fail("a key did not change the count on the screen to 1", seen)
print("ok: a key typed into the terminal changed the screen to count 1")

os.write(fd, b"\x03")
read_until(lambda text: False, 3)
deadline = time.time() + 30
status = None
while time.time() < deadline:
    done, raw = os.waitpid(pid, os.WNOHANG)
    if done:
        status = os.waitstatus_to_exitcode(raw)
        break
    try:
        data = os.read(fd, 65536)
        seen += data
    except OSError:
        pass
    time.sleep(0.1)
if status is None:
    fail("Ctrl-C did not end the app", seen)
if status != 0:
    fail(f"the app exited with status {status}, not 0", seen)
print("ok: Ctrl-C ended the app with status 0")
if b"\x1b[?1049l" not in seen:
    fail("the app did not leave the alternate screen", seen)
print("ok: the app left the alternate screen and restored the terminal")
