#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery (Plan 001): runs a built app the way a person who has never
# installed Ruby would, and fails unless it behaves. CI delivers two:
# examples/hello, a lone main.rb, and examples/my_cool_app, a gem whose
# exe/my_cool_app needs a pure-Ruby gem and a native one (ADR 005).
#
#   deliver.sh ARCHIVE PROBE_ARCHIVE EXPECTED [--no-ruby-installed]
#
# ARCHIVE is NAME-PLATFORM.tar.gz as fledge build wrote it, and
# PROBE_ARCHIVE the parity probe (test/fixtures/parity) built the same
# way, which reports what a child Ruby sees: Parity-PLATFORM.tar.gz, a
# lone script, for hello, and ParityBundle-PLATFORM.tar.gz, the probe as
# a gem-shaped app's program (Parity.gem_probe), for my_cool_app. EXPECTED
# is the one line the app must print: for hello, "Hello from Ruby 4.0.9
# on RUBY_PLATFORM"; for my_cool_app, what bundle exec exe/my_cool_app
# printed on the computer that built it. With --no-ruby-installed, the
# computer itself must have no Ruby on its PATH (a fresh container);
# without it, the app still runs with a PATH that holds no Ruby, whatever
# the runner has installed.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

archive=$1
probe_archive=$2
expected=$3

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
folder=$(basename "$archive" .tar.gz)
# NAME-PLATFORM, where every PLATFORM here (arm64-darwin, x86_64-linux,
# aarch64-linux) has one hyphen.
name=${folder%-*-*}

# Unpack somewhere the app was never built, under a path with spaces and
# characters outside ASCII: a C locale reads those as invalid bytes
# unless the launcher coerces it to UTF-8.
place="$work/My Apps/Ünïcödé 日本"
mkdir -p "$place"
tar -xzf "$archive" -C "$place"
tar -xzf "$probe_archive" -C "$place"
root="$place/$folder"
app="$root/$name"
probe_folder=$(basename "$probe_archive" .tar.gz)
probe="$place/$probe_folder/${probe_folder%-*-*}"
entry=$(sed -n 's/^entry = //p' "$root/fledge.cfg")
[ -n "$entry" ] || fail "$root/fledge.cfg names no entry"
[ -x "$app" ] || fail "$app is not executable after unpacking"
[ -x "$probe" ] || fail "$probe is not executable after unpacking"

# The app carries the notices the license audit wrote (ADR 004): every
# component and license text, and the SBOM; on Linux, libxcrypt's
# replaceability and where its source is.
[ -s "$root/notices/sbom.spdx.json" ] || fail "the app has no notices/sbom.spdx.json"
grep -q "^This app was built with Fledge" "$root/notices/NOTICES.txt" || fail "the app has no notices/NOTICES.txt from the license audit"
case "$(uname -s)" in
  Linux)
    grep -qx "  lib/libcrypt.so.2" "$root/notices/NOTICES.txt" || fail "NOTICES.txt does not say lib/libcrypt.so.2 is replaceable"
    grep -q -- "-lgpl-sources.tar.gz$" "$root/notices/NOTICES.txt" || fail "NOTICES.txt does not say where libxcrypt's source is"
    ;;
esac
# An app with a Gemfile carries its gems' notices too (ADR 005).
if [ -f "$root/app/Gemfile" ]; then
  grep -q "^THE APP'S OWN GEMS$" "$root/notices/GEMS.txt" || fail "the app has gems but no notices/GEMS.txt"
fi
echo "ok: the app carries its notices and SBOM"

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
# Nothing the app runs may write into its own folder: a Bundler that
# touched or rewrote the Gemfile.lock would, on every start.
untouched="$work/untouched"
touch "$untouched"
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

# plant_bundler_config HOME: a ~/.bundle/config that points Bundler at
# the evil folder, asks for gems compiled from source, leaves out the
# app's own gems, and installs whatever is missing.
plant_bundler_config() {
  mkdir -p "$1/.bundle"
  cat >"$1/.bundle/config" <<CONFIG
---
BUNDLE_GEMFILE: "$evil/Gemfile"
BUNDLE_PATH: "$evil"
BUNDLE_FORCE_RUBY_PLATFORM: "true"
BUNDLE_WITHOUT: "default"
BUNDLE_AUTO_INSTALL: "true"
CONFIG
}

dot_gem_home="$work/dot-gem-home"
plant_json "$dot_gem_home/.gem/ruby/4.0.0"
plant_bundler_config "$dot_gem_home"
xdg_home="$work/xdg-home"
plant_json "$xdg_home/.local/share/gem/ruby/4.0.0"

check "a json gem in ~/.gem" 0 env -i PATH="$empty" HOME="$dot_gem_home" "$app"
check "a json gem in ~/.local/share/gem" 0 env -i PATH="$empty" HOME="$xdg_home" "$app"
check "hostile environment" 0 env -i PATH="$empty" HOME="$dot_gem_home" \
  RUBYLIB="$evil" RUBYOPT="-rnonexistent" RUBYSHELL=/bin/false \
  GEM_HOME="$dot_gem_home/.gem/ruby/4.0.0" GEM_PATH="$dot_gem_home/.gem/ruby/4.0.0" \
  GEM_SPEC_CACHE="$evil" GEMRC="$evil/json.rb" \
  BUNDLE_GEMFILE="$evil/Gemfile" BUNDLE_PATH="$evil" BUNDLER_SETUP="$evil/bundler_setup.rb" \
  BUNDLE_APP_CONFIG="$evil" BUNDLE_FROZEN=false BUNDLE_WITHOUT=default BUNDLER_VERSION=2.1.0 \
  RUBYGEMS_GEMDEPS=- RUBY_YJIT_ENABLE=0 LD_LIBRARY_PATH="$evil/lib" \
  "$app"

check "exit status 3 reaches the caller" 3 env -i PATH="$empty" HOME="$home" "$app" 3

# Found on PATH by a bare name, through a symlink, from another folder:
# the launcher must still find the runtime it really lives in.
links="$work/links"
mkdir -p "$links"
ln -s "$app" "$links/app-link"
check "run through a symlink on PATH" 0 env -i PATH="$links" HOME="$home" app-link

changed=$(find "$root" -newer "$untouched" | head -n 5)
[ -z "$changed" ] || fail "running the app changed files in its folder: $changed"
echo "ok: the app wrote nothing into its own folder"

# The person's own Ruby settings are hidden from the app's boot only
# (ADR 003): the app's gems stay the runtime's, and what the app starts
# sees the person's GEM_HOME and RUBYOPT. Without a Gemfile, that is any
# Ruby the app starts through RbConfig.ruby, the runtime's own bin/ruby,
# as under ruby main.rb. With one, the app's ENV is bundle exec's, with
# Bundler's GEM_HOME over the person's, and a Ruby started inside
# Bundler.with_original_env or with_unbundled_env, as a Bundler app
# starts a person's own tools, sees theirs (ADR 005).
person_gems="$work/person gems"
mkdir -p "$person_gems"
# person_sees COMMAND NAME: what the probe's COMMAND says a child Ruby
# sees as NAME, for a person whose GEM_HOME and RUBYOPT are set.
person_sees() {
  (cd / && env -i PATH="$empty" HOME="$home" GEM_HOME="$person_gems" RUBYOPT=-W0 "$probe" "$1" "$2")
}
if [ -f "$place/$probe_folder/app/Gemfile" ]; then
  for command in original-child-env unbundled-child-env; do
    seen=$(person_sees "$command" GEM_HOME)
    [ "$seen" = "$person_gems" ] || fail "$command: a child Ruby saw GEM_HOME as '$seen', not the person's '$person_gems'"
    seen=$(person_sees "$command" RUBYOPT)
    [ "$seen" = "-W0" ] || fail "$command: a child Ruby saw RUBYOPT as '$seen', not the person's '-W0'"
  done
  echo "ok: Bundler.with_original_env and with_unbundled_env give a child Ruby the person's GEM_HOME and RUBYOPT"
else
  seen=$(person_sees child-env GEM_HOME)
  [ "$seen" = "$person_gems" ] || fail "a child Ruby saw GEM_HOME as '$seen', not the person's '$person_gems'"
  seen=$(person_sees child-env RUBYOPT)
  [ "$seen" = "-W0" ] || fail "a child Ruby saw RUBYOPT as '$seen', not the person's '-W0'"
  echo "ok: a child Ruby sees the person's GEM_HOME and RUBYOPT"
fi
gem_path=$(cd / && env -i PATH="$empty" HOME="$home" GEM_HOME="$person_gems" RUBYOPT=-W0 "$probe" gem-path)
case "$gem_path" in
  *"$person_gems"*) fail "the app's own Gem.path holds the person's GEM_HOME: $gem_path" ;;
esac
echo "ok: the app's own gems ignore the person's GEM_HOME"

# A broken app names itself, not Ruby, on standard error, and exits with
# EX_NOINPUT (66) when the program it runs, app/ENTRY, is missing (ADR
# 002).
program="$root/app/$entry"
mv "$program" "$program.away"
set +e
(cd / && env -i PATH="$empty" HOME="$home" "$app") >"$work/out" 2>"$work/err"
actual=$?
set -e
mv "$program.away" "$program"
# The launcher names the file by its real path, symlinks resolved (macOS's
# temporary folder is a symlink into /private).
real_program="$(cd "$root/app" && pwd -P)/$entry"
if [ "$actual" -ne 66 ] || [ -s "$work/out" ] || [ "$(cat "$work/err")" != "$name: this app is incomplete: $real_program is missing" ]; then
  echo "--- stdout"; cat "$work/out"
  echo "--- stderr"; cat "$work/err"
  fail "an app without app/$entry: exit status $actual (expected 66), output above"
fi
echo "ok: an app without app/$entry says so and exits 66"

case "$(uname -s)" in
  Linux)
    # The launcher and Ruby's own bin/ruby both load the runtime's
    # libcrypt, the LGPL library a person may replace, and neither has
    # one of its own. bin/ruby finds it through $ORIGIN/../lib, so the
    # loader's path is compared by the folder it really is.
    lib=$(cd "$root/lib" && pwd -P)
    for program in "$app" "$root/bin/ruby"; do
      crypt=$(ldd "$program" | sed -n 's/^[[:space:]]*libcrypt\.so\.[0-9]* => \(.*\) (0x[0-9a-f]*)$/\1/p')
      folder=$( (cd "$(dirname "$crypt")" 2>/dev/null && pwd -P) || echo none)
      case "$folder/$(basename "$crypt")" in
        "$lib/libcrypt.so."*) echo "ok: $(basename "$program") loads libcrypt from the runtime ($crypt)" ;;
        *) ldd "$program"; fail "$program resolves libcrypt to '$crypt', not the runtime's lib/" ;;
      esac
    done
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
