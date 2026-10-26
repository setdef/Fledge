#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery (Plan 001): runs a built examples/hello the way a person who
# has never installed Ruby would, and fails unless it behaves.
#
#   deliver.sh ARCHIVE PROBE_ARCHIVE RUBY_PLATFORM [--no-ruby-installed]
#
# ARCHIVE is hello-PLATFORM.tar.gz as fledge build wrote it, and
# PROBE_ARCHIVE parity-PLATFORM.tar.gz, the parity probe
# (test/fixtures/parity), which reports what a child Ruby sees.
# RUBY_PLATFORM is what the app must report: arm64-darwin23,
# x86_64-linux, or aarch64-linux. With --no-ruby-installed, the computer
# itself must have no Ruby on its PATH (a fresh container); without it,
# the app still runs with a PATH that holds no Ruby, whatever the runner
# has installed.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

archive=$1
probe_archive=$2
platform=$3
expected="Hello from Ruby 4.0.9 on $platform"

fail() {
  echo "::error::Delivery: $*" >&2
  exit 1
}

if [ "${4:-}" = "--no-ruby-installed" ] && command -v ruby >/dev/null 2>&1; then
  fail "this computer has Ruby at $(command -v ruby), so it cannot prove the app needs none"
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
archive=$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")
probe_archive=$(cd "$(dirname "$probe_archive")" && pwd)/$(basename "$probe_archive")
name=$(basename "$archive" .tar.gz)

# Unpack somewhere the app was never built, under a path with spaces and
# characters outside ASCII: a C locale reads those as invalid bytes
# unless the launcher coerces it to UTF-8.
place="$work/My Apps/Ünïcödé 日本"
mkdir -p "$place"
tar -xzf "$archive" -C "$place"
tar -xzf "$probe_archive" -C "$place"
root="$place/$name"
app="$root/hello"
probe="$place/$(basename "$probe_archive" .tar.gz)/parity"
[ -x "$app" ] || fail "$app is not executable after unpacking"
[ -x "$probe" ] || fail "$probe is not executable after unpacking"

# The app runs with a PATH that holds nothing at all, so no Ruby is on
# it, whatever this computer has installed.
empty="$work/empty-path"
mkdir -p "$empty"
if env -i PATH="$empty" /bin/sh -c 'command -v ruby' >/dev/null 2>&1; then
  fail "ruby is still reachable on the app's PATH"
fi
echo "No Ruby on the app's PATH. This computer's own: $(command -v ruby || echo none)"

# check LABEL STATUS COMMAND...: runs COMMAND from /, and fails unless it
# prints exactly the expected line, nothing on standard error, and exits
# with STATUS.
check() {
  label=$1
  status=$2
  shift 2
  set +e
  (cd / && "$@") >"$work/out" 2>"$work/err"
  actual=$?
  set -e
  # The x keeps command substitution from dropping trailing newlines, so
  # the output must be exactly one line.
  printed=$(cat "$work/out"; printf x)
  if [ "$printed" != "$expected
x" ] || [ -s "$work/err" ] || [ "$actual" -ne "$status" ]; then
    echo "--- stdout"; cat "$work/out"
    echo "--- stderr"; cat "$work/err"
    fail "$label: exit status $actual (expected $status), output above (expected \"$expected\")"
  fi
  echo "ok: $label"
}

home="$work/home"
mkdir -p "$home"
check "clean environment" 0 env -i PATH="$empty" HOME="$home" "$app"

# A hostile environment: everything a Ruby developer's shell might set,
# pointed at code that raises if it ever loads. A json 99 in the user's
# gem folder (Gem.user_dir: ~/.gem/ruby/4.0.0, or
# ~/.local/share/gem/ruby/4.0.0 when ~/.gem does not exist) shadows the
# runtime's json if RubyGems searches it; a libcrypt in LD_LIBRARY_PATH
# breaks the launcher if the dynamic linker prefers it to the runtime's.
evil="$work/evil"
mkdir -p "$evil/lib"
for file in json nonexistent bundler_setup; do
  echo 'raise "Delivery: the user'"'"'s Ruby environment leaked into the app"' >"$evil/$file.rb"
done
echo "not a library" >"$evil/lib/libcrypt.so.2"

# plant_json GEM_FOLDER: installs the leaking json 99 into GEM_FOLDER.
plant_json() {
  mkdir -p "$1/gems/json-99.0.0/lib" "$1/specifications"
  cp "$evil/json.rb" "$1/gems/json-99.0.0/lib/json.rb"
  cat >"$1/specifications/json-99.0.0.gemspec" <<'SPEC'
Gem::Specification.new do |s|
  s.name = "json"
  s.version = "99.0.0"
  s.summary = "leak"
  s.authors = ["leak"]
  s.files = ["lib/json.rb"]
end
SPEC
}

dot_gem_home="$work/dot-gem-home"
plant_json "$dot_gem_home/.gem/ruby/4.0.0"
xdg_home="$work/xdg-home"
plant_json "$xdg_home/.local/share/gem/ruby/4.0.0"

check "a json gem in ~/.gem" 0 env -i PATH="$empty" HOME="$dot_gem_home" "$app"
check "a json gem in ~/.local/share/gem" 0 env -i PATH="$empty" HOME="$xdg_home" "$app"
check "hostile environment" 0 env -i PATH="$empty" HOME="$dot_gem_home" \
  RUBYLIB="$evil" RUBYOPT="-rnonexistent" RUBYSHELL=/bin/false \
  GEM_HOME="$dot_gem_home/.gem/ruby/4.0.0" GEM_PATH="$dot_gem_home/.gem/ruby/4.0.0" \
  GEM_SPEC_CACHE="$evil" GEMRC="$evil/json.rb" \
  BUNDLE_GEMFILE="$evil/Gemfile" BUNDLE_PATH="$evil" BUNDLER_SETUP="$evil/bundler_setup.rb" \
  RUBYGEMS_GEMDEPS=- RUBY_YJIT_ENABLE=0 LD_LIBRARY_PATH="$evil/lib" \
  "$app"

check "exit status 3 reaches the caller" 3 env -i PATH="$empty" HOME="$home" "$app" 3

# Found on PATH by a bare name, through a symlink, from another folder:
# the launcher must still find the runtime it really lives in.
links="$work/links"
mkdir -p "$links"
ln -s "$app" "$links/hello-link"
check "run through a symlink on PATH" 0 env -i PATH="$links" HOME="$home" hello-link

# The person's own Ruby settings are hidden from the app's boot only
# (ADR 003): the app's gems stay the runtime's, and a Ruby the app starts
# through RbConfig.ruby, the runtime's own bin/ruby, sees the person's
# GEM_HOME, as it would under ruby main.rb.
person_gems="$work/person gems"
mkdir -p "$person_gems"
seen=$(cd / && env -i PATH="$empty" HOME="$home" GEM_HOME="$person_gems" "$probe" child-env GEM_HOME)
[ "$seen" = "$person_gems" ] || fail "a child Ruby saw GEM_HOME as '$seen', not the person's '$person_gems'"
echo "ok: a child Ruby sees the person's GEM_HOME"
gem_path=$(cd / && env -i PATH="$empty" HOME="$home" GEM_HOME="$person_gems" "$probe" gem-path)
case "$gem_path" in
  *"$person_gems"*) fail "the app's own Gem.path holds the person's GEM_HOME: $gem_path" ;;
esac
echo "ok: the app's own gems ignore the person's GEM_HOME"

# A broken app names itself, not Ruby, on standard error, and exits with
# EX_NOINPUT (66) when its app/main.rb is missing (ADR 002).
main="$root/app/main.rb"
mv "$main" "$main.away"
set +e
(cd / && env -i PATH="$empty" HOME="$home" "$app") >"$work/out" 2>"$work/err"
actual=$?
set -e
mv "$main.away" "$main"
# The launcher names the file by its real path, symlinks resolved (macOS's
# temporary folder is a symlink into /private).
real_main="$(cd "$root/app" && pwd -P)/main.rb"
if [ "$actual" -ne 66 ] || [ -s "$work/out" ] || [ "$(cat "$work/err")" != "hello: this app is incomplete: $real_main is missing" ]; then
  echo "--- stdout"; cat "$work/out"
  echo "--- stderr"; cat "$work/err"
  fail "an app without main.rb: exit status $actual (expected 66), output above"
fi
echo "ok: an app without main.rb says so and exits 66"

case "$(uname -s)" in
  Linux)
    crypt=$(ldd "$app" | sed -n 's/^[[:space:]]*libcrypt\.so\.[0-9]* => \(.*\) (0x[0-9a-f]*)$/\1/p')
    case "$crypt" in
      "$root/lib/libcrypt.so."*) echo "ok: libcrypt loads from the runtime ($crypt)" ;;
      *) ldd "$app"; fail "libcrypt resolves to '$crypt', not the runtime's lib/" ;;
    esac
    ;;
  Darwin)
    otool -L "$app" | tail -n +2 | while read -r library _; do
      case "$library" in
        /usr/lib/* | /System/Library/*) ;;
        *) fail "the launcher links $library, which macOS does not ship" ;;
      esac
    done
    echo "ok: the launcher links only libraries macOS ships"
    ;;
esac

echo "Delivered: $expected"
