# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Runs the Fledge Check app in a pseudo-terminal of 100 by 40 cells (macOS and Linux).

The PATH holds no Ruby, and a Ruby's settings are in the environment.
The screen must show the facts, redraw by itself, echo a key, write a
report on r, and exit with status 0 on q; a second run must end on
Ctrl-C by the signal Ruby's Interrupt raises.

    python3 -I deliver.py PROGRAM
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
    print(f"::error::Fledge Check: {message}")
    print(repr(seen[:3500]))
    sys.exit(1)


class Run:
    def __init__(self, program, work):
        home = os.path.join(work, "home")
        os.makedirs(home, exist_ok=True)
        env = {
            "PATH": os.path.join(work, "empty"),
            "HOME": home,
            "TERM": "xterm-256color",
            "LANG": "en_US.UTF-8" if sys.platform == "darwin" else "C.UTF-8",
            "RUBYOPT": "-rnonexistent_library_a_person_set",
            "RUBYLIB": home,
            "GEM_HOME": os.path.join(home, "gems"),
        }
        os.makedirs(env["PATH"], exist_ok=True)
        self.seen = b""
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 100, 0, 0))
            os.chdir(work)
            os.execve(program, [program], env)

    def text(self, since=0):
        return CONTROL.sub(b"", self.seen[since:]).decode("utf-8", "replace")

    def read_until(self, test, seconds):
        deadline = time.time() + seconds
        while time.time() < deadline:
            if test(self.text()):
                return True
            ready, _, _ = select.select([self.fd], [], [], 0.2)
            if ready:
                try:
                    data = os.read(self.fd, 65536)
                except OSError:
                    return test(self.text())
                if not data:
                    return test(self.text())
                self.seen += data
        return False

    def status(self, seconds):
        deadline = time.time() + seconds
        while time.time() < deadline:
            done, raw = os.waitpid(self.pid, os.WNOHANG)
            if done:
                return os.waitstatus_to_exitcode(raw)
            try:
                self.seen += os.read(self.fd, 65536)
            except OSError:
                pass
            time.sleep(0.1)
        return None


program = os.path.abspath(sys.argv[1])
work = tempfile.mkdtemp()
run = Run(program, work)
EXPECTED = [
    (r"Fledge\s*app:\s*yes", "that it runs from a Fledge app"),
    (r"Operating\s*system", "the operating system"),
    (r"Processor", "the processor"),
    (r"RbConfig\.ruby", "where its Ruby is"),
    (r"Gem\.dir", "where its gems are"),
    (r"Encodings", "the encodings"),
    (r"Color\s*depth", "the color depth"),
    (r"RUBYOPT", "RUBYOPT"),
    (r"Clock\s*\d\d:\d\d:\d\d", "a clock"),
]
if not run.read_until(lambda t: all(re.search(p, t) for p, _ in EXPECTED), 90):
    missing = [what for pattern, what in EXPECTED if not re.search(pattern, run.text())]
    fail(f"the screen does not show {', '.join(missing)}", run.seen)
print("ok: the screen shows the facts")
if b"\x1b[?1049h" not in run.seen:
    fail("the app did not enter the alternate screen", run.seen)

mark = len(run.seen)
run.read_until(lambda t: False, 2.5)
after = run.text(mark)
if not re.search(r"\d", after):
    fail("nothing was redrawn in 2.5 seconds", run.seen)
print("ok: the clock and frame counter redraw by themselves")

mark = len(run.seen)
os.write(run.fd, b"w")
if not run.read_until(lambda t: "w" in run.text(mark), 20):
    fail("a key did not show as the last key", run.seen)
print("ok: the last key typed shows on the screen")

os.write(run.fd, b"r")
report = os.path.join(work, "fledge-check-report.txt")
if not run.read_until(lambda t: os.path.exists(report), 20):
    fail("r did not write fledge-check-report.txt in the current folder", run.seen)
body = open(report, encoding="utf-8").read()
if "Fledge app: yes" not in body or "Ruby:" not in body:
    fail("the report lacks the facts", run.seen)
print("ok: r wrote the report:")
print(body)

os.write(run.fd, b"q")
status = run.status(30)
if status is None:
    fail("q did not end the app", run.seen)
if status != 0:
    fail(f"q ended the app with status {status}, not 0", run.seen)
print("ok: q ended the app with status 0")
if b"\x1b[?1049l" not in run.seen:
    fail("the app did not leave the alternate screen", run.seen)
print("ok: the terminal was restored")

second = Run(program, work)
if not second.read_until(lambda t: "Gem.dir" in t, 60):
    fail("the second run never showed its screen", second.seen)
os.write(second.fd, b"\x03")
status = second.status(30)
if status is None:
    fail("Ctrl-C did not end the app", second.seen)
print(f"ok: Ctrl-C ended the app with status {status} (-2 is SIGINT, as Ruby's Interrupt ends a program)")
if status != -2:
    fail(f"Ctrl-C ended the app with status {status}, not by SIGINT", second.seen)
if b"\x1b[?1049l" not in second.seen:
    fail("Ctrl-C did not restore the terminal", second.seen)
print("ok: Ctrl-C restored the terminal")
