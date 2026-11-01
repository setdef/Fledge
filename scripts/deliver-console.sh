#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery of the console (ADR 015): runs the console probe
# (test/fixtures/console) in a terminal of its own, a pseudo-terminal
# that script(1) opens, as a person runs an app in Terminal or a Linux
# terminal emulator, and ends it as they would:
#
#   interrupt  Ctrl-C, typed into the terminal, which the terminal's
#              line discipline turns into SIGINT for the foreground
#              process group. Ruby raises Interrupt; uncaught, it runs
#              ensure clauses and at_exit hooks, prints its message, and
#              ends the process by SIGINT, which a shell reports as 130.
#   hangup     The terminal closing, which sends SIGHUP to the
#              foreground process group (POSIX, "Closing a Terminal
#              Device File"; a shell sends it on to its jobs). Ruby
#              raises SignalException SIGHUP and ends by SIGHUP, 129.
#
# Each must end the app as it ends ruby main.rb, with what the app
# recorded, its exit status as the shell inside the terminal saw it,
# and what the terminal showed. The launcher is the interpreter here
# (libruby is linked into it), so nothing of Fledge stands between the
# signal and Ruby's own handler.
#
#   deliver-console.sh ARCHIVE
#   deliver-console.sh --reference RUBY MAIN_RB
#
# ARCHIVE is Console-PLATFORM.tar.gz as fledge build wrote it. With
# --reference, it runs MAIN_RB, the probe's own main.rb, with RUBY, as
# ruby main.rb, and expects exactly the same; CI's Test jobs run that
# with the Ruby the runtime came from, and Delivery the built app.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

fail() {
  echo "::error::Delivery (console): $*" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ "$1" = "--reference" ]; then
  command_line="'$2' '$3'"
  label="ruby main.rb"
else
  archive=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
  folder=$(basename "$archive" .tar.gz)
  mkdir -p "$work/apps"
  tar -xzf "$archive" -C "$work/apps"
  command_line="'$work/apps/$folder/${folder%-*-*}'"
  label="the built app"
fi

# A locale every runner has, so that Ruby's choice of encoding is the
# terminal's, not a bare C locale's, which the launcher turns into UTF-8
# and ruby does not (ADR 003, section 5).
case "$(uname -s)" in
  Darwin) locale=en_US.UTF-8 ;;
  *) locale=C.UTF-8 ;;
esac

# run SCENARIO: runs the probe in a new terminal, through a shell that
# records the probe's process group and exit status, waits for it to be
# ready, ends it as SCENARIO says, and leaves the probe's record in
# $work/SCENARIO.log and what the terminal showed in $work/SCENARIO.tty.
run() {
  scenario=$1
  log="$work/$scenario.log"
  : >"$log"
  # The shell traps both signals so that it outlives the probe and can
  # record its status; a trapped signal is reset to its default in the
  # programs the shell starts, so the probe gets Ruby's own handling.
  cat >"$work/$scenario.sh" <<SHELL
echo "shell \$\$" >>'$log'
trap : INT HUP
env -i PATH=/usr/bin:/bin HOME='$work' LC_ALL=$locale $command_line '$log'
echo "status \$?" >>'$log'
SHELL
  # The keyboard is a pipe, as macOS's script(1) reads no FIFO, that
  # types Ctrl-C when told to and stays open, as a person's does, until
  # the probe has ended: script sends end-of-file on when it closes.
  rm -f "$work/type" "$work/done"
  keyboard() {
    until [ -e "$work/done" ]; do
      if [ -e "$work/type" ]; then
        printf '\003'
        rm -f "$work/type"
      fi
      sleep 0.1
    done
  }
  # The terminal runs in the foreground: a program a script starts in
  # the background starts with SIGINT ignored (POSIX, "Asynchronous
  # Lists"), which Ruby would keep, so Ctrl-C would do nothing. What
  # ends the probe runs in the background instead.
  end_probe "$scenario" &
  case "$(uname -s)" in
    Darwin) keyboard | script -q "$work/$scenario.tty" /bin/sh "$work/$scenario.sh" >/dev/null || true ;;
    *) keyboard | SHELL=/bin/sh script -q -e -c "/bin/sh '$work/$scenario.sh'" "$work/$scenario.tty" >/dev/null || true ;;
  esac
  wait
  if [ -e "$work/timeout" ]; then
    cat "$log" "$work/$scenario.tty" || true
    fail "$label $(cat "$work/timeout") ($scenario)"
  fi
}

# end_probe SCENARIO: waits for the probe to be ready, ends it as
# SCENARIO says, waits for the shell to record its status, and closes
# the keyboard, whatever happens; on a failure, says why in
# $work/timeout.
end_probe() {
  set +e
  log="$work/$1.log"
  rm -f "$work/timeout"
  if await '^ready$' "$log"; then
    case "$1" in
      interrupt) touch "$work/type" ;;
      hangup)
        # The terminal's foreground process group: the shell and the
        # probe it started, each by its process ID, which every shell's
        # kill takes alike.
        shell=$(sed -n 's/^shell //p' "$log")
        kill -HUP "$shell" $(pgrep -P "$shell") || echo "could not hang up the shell, $shell, and the probe" >"$work/timeout"
        ;;
    esac
    await '^status ' "$log" || echo "did not end" >>"$work/timeout"
  else
    echo "never got ready in its terminal" >"$work/timeout"
  fi
  # A probe that did not end, as one started with SIGINT ignored would
  # not, is stopped, so the terminal closes and the failure is reported.
  if [ -e "$work/timeout" ]; then
    shell=$(sed -n 's/^shell //p' "$log")
    [ -z "$shell" ] || kill -KILL $(pgrep -P "$shell") "$shell" 2>/dev/null
  fi
  touch "$work/done"
}

# await PATTERN FILE: waits up to 30 seconds for a line of FILE to match.
await() {
  waited=0
  until grep -q "$1" "$2"; do
    waited=$((waited + 1))
    [ "$waited" -le 300 ] || return 1
    sleep 0.1
  done
}

# expect SCENARIO EXPECTED_RECORD TERMINAL_PATTERN: fails unless the
# probe recorded exactly EXPECTED_RECORD, and the terminal showed the
# line outside ASCII byte for byte and a line matching TERMINAL_PATTERN:
# for Ctrl-C, Ruby's message for the Interrupt; Ruby prints none for a
# SignalException it ends by.
expect() {
  scenario=$1
  sed '/^shell /d' "$work/$scenario.log" >"$work/$scenario.record"
  printf '%s\n' "$2" >"$work/$scenario.expected"
  if ! diff "$work/$scenario.expected" "$work/$scenario.record"; then
    fail "$label recorded the above on $scenario, not what ruby main.rb records"
  fi
  grep -q "$(printf 'caf\303\251 \342\234\223')" "$work/$scenario.tty" ||
    { cat "$work/$scenario.tty"; fail "the terminal did not show the probe's UTF-8 line byte for byte ($scenario)"; }
  grep -Eq "$3" "$work/$scenario.tty" ||
    { cat "$work/$scenario.tty"; fail "the terminal did not show a line matching /$3/ ($scenario)"; }
  echo "ok: $label, $scenario"
}

run interrupt
expect interrupt "locale UTF-8
external UTF-8
ready
ensure ran (Interrupt: )
at_exit ran
status 130" ":[0-9]+:in .*sleep.*Interrupt"

run hangup
expect hangup "locale UTF-8
external UTF-8
ready
ensure ran (SignalException: SIGHUP)
at_exit ran
status 129" ""

echo "Delivered: Ctrl-C and a hangup end $label through Ruby's own handlers"
