#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Spike (experiment/path-probe only): runs a built path probe in each
# scenario and keeps what it reports.
#
#   drive.sh ARCHIVE OUTDIR LABEL
#
# ARCHIVE is NAME-PLATFORM.tar.gz as fledge build wrote it. Each run
# writes OUTDIR/LABEL--RUN.jsonl (one line per generation of the restart
# chain) and OUTDIR/LABEL--RUN.result (exit status and standard error).

set -u

archive=$1
outdir=$2
label=$3
mkdir -p "$outdir"
outdir=$(cd "$outdir" && pwd -P)
archive=$(cd "$(dirname "$archive")" && pwd -P)/$(basename "$archive")
folder=$(basename "$archive" .tar.gz)

work=$(mktemp -d)
work=$(cd "$work" && pwd -P)
empty="$work/empty"
home="$work/home"
evil="$work/evil"
person_gems="$work/person gems"
mkdir -p "$empty" "$home" "$evil" "$person_gems"
case "$(uname -s)" in
  Darwin) utf8=en_US.UTF-8 ;;
  *) utf8=C.UTF-8 ;;
esac
printf 'abort "the person RUBYLIB json.rb shadowed the runtime json"\n' > "$evil/json.rb"

# The program a person runs inside a placed copy of the app.
program_in() {
  if [ -d "$1/$folder" ] && ls "$1/$folder" | grep -q '\.app$'; then
    app=$(ls -d "$1/$folder"/*.app)
    name=$(basename "$app" .app)
    echo "$app/Contents/MacOS/$name"
  else
    for candidate in "$1/$folder"/*; do
      case "$candidate" in *.desktop | *.png | *.svg | */AppRun) continue ;; esac
      if [ -f "$candidate" ] && [ -x "$candidate" ]; then echo "$candidate"; return; fi
    done
  fi
}

# run RUN ENVKIND MODE PLACE
run() {
  out="$outdir/$label--$1.jsonl"
  result="$outdir/$label--$1.result"
  rm -f "$out"
  program=$(program_in "$4")
  case "$2" in
    clean)
      (cd / && env -i PATH="$empty" HOME="$home" "$program" "$out" "$3" 0) 2>"$work/err"
      ;;
    utf8)
      (cd / && env -i PATH="$empty" HOME="$home" LANG="$utf8" "$program" "$out" "$3" 0) 2>"$work/err"
      ;;
    person)
      (cd / && env -i PATH="$empty" HOME="$home" LANG="$utf8" RUBYOPT=-W0 RUBYLIB="$evil" GEM_HOME="$person_gems" \
        GEM_PATH="$person_gems" "$program" "$out" "$3" 0) 2>"$work/err"
      ;;
    hostile)
      (cd / && env -i PATH="$empty" HOME="$home" \
        RUBYLIB="$evil" RUBYOPT="-rnonexistent" RUBYSHELL=/bin/false \
        GEM_HOME="$home/.gem/ruby/4.0.0" GEM_PATH="$home/.gem/ruby/4.0.0" \
        GEM_SPEC_CACHE="$evil" GEMRC="$evil/json.rb" \
        BUNDLE_GEMFILE="$evil/Gemfile" BUNDLE_PATH="$evil" BUNDLER_SETUP="$evil/bundler_setup.rb" \
        BUNDLE_APP_CONFIG="$evil" BUNDLE_FROZEN=false BUNDLE_WITHOUT=default BUNDLER_VERSION=2.1.0 \
        RUBYGEMS_GEMDEPS=- RUBY_YJIT_ENABLE=0 LD_LIBRARY_PATH="$evil/lib" \
        "$program" "$out" "$3" 0) 2>"$work/err"
      ;;
  esac
  status=$?
  printf '{"run":"%s","env":"%s","mode":"%s","place":"%s","program":"%s","status":%s}\n' \
    "$1" "$2" "$3" "$4" "$program" "$status" > "$result"
  cat "$work/err" >> "$result"
  echo "== $label $1: status $status"
  cat "$work/err"
  [ -f "$out" ] && cat "$out"
}

# Built: the folder fledge build left in dist beside the archive, where
# the developer built it.
built=$(dirname "$archive")
if [ -d "$built/$folder" ]; then
  run built-clean-ruby clean ruby "$built"
fi

unpacked="$work/unpacked"
mkdir -p "$unpacked"
tar xzf "$archive" -C "$unpacked"
run unpacked-clean-ruby clean ruby "$unpacked"

moved="$work/moved/elsewhere"
mkdir -p "$moved"
mv "$unpacked/$folder" "$moved/"
run moved-clean-ruby clean ruby "$moved"

place="$work/My Apps/Ünïcödé 日本"
mkdir -p "$place"
mv "$moved/$folder" "$place/"
for envkind in clean utf8 person hostile; do
  for mode in ruby launcher scrubbed; do
    run "unicode-$envkind-$mode" "$envkind" "$mode" "$place"
  done
done

# A macOS app bundle, started by Launch Services as Finder starts it.
case "$(uname -s)" in
  Darwin)
    if ls "$place/$folder" | grep -q '\.app$'; then
      app=$(ls -d "$place/$folder"/*.app)
      for mode in ruby launcher scrubbed; do
        out="$outdir/$label--open-clean-$mode.jsonl"
        rm -f "$out"
        open -n -W "$app" --args "$out" "$mode" 0 2>"$work/err"
        echo "{\"run\":\"open-clean-$mode\",\"status\":$?}" > "$outdir/$label--open-clean-$mode.result"
        echo "== $label open-clean-$mode"; cat "$out" 2>/dev/null
        out="$outdir/$label--open-hostile-$mode.jsonl"
        rm -f "$out"
        open -n -W --env RUBYOPT=-rnonexistent --env RUBYLIB="$evil" --env GEM_HOME="$person_gems" \
          --env BUNDLE_GEMFILE="$evil/Gemfile" "$app" --args "$out" "$mode" 0 2>"$work/err"
        echo "{\"run\":\"open-hostile-$mode\",\"status\":$?}" > "$outdir/$label--open-hostile-$mode.result"
        echo "== $label open-hostile-$mode"; cat "$out" 2>/dev/null
      done
    fi
    ;;
esac
# A Linux AppImage beside the archive, run as a person runs one, with
# FUSE, whose fusermount must be on PATH.
appimage="$(dirname "$archive")/$folder.AppImage"
if [ -f "$appimage" ]; then
  cp "$appimage" "$place/probe.AppImage"
  chmod +x "$place/probe.AppImage"
  for envkind in clean hostile; do
    for mode in ruby launcher; do
      runname="appimage-$envkind-$mode"
      out="$outdir/$label--$runname.jsonl"
      rm -f "$out"
      if [ "$envkind" = clean ]; then
        (cd / && env -i PATH=/usr/bin:/bin HOME="$home" "$place/probe.AppImage" "$out" "$mode" 0) 2>"$work/err"
      else
        (cd / && env -i PATH=/usr/bin:/bin HOME="$home" RUBYLIB="$evil" RUBYOPT="-rnonexistent" \
          GEM_HOME="$person_gems" BUNDLE_GEMFILE="$evil/Gemfile" "$place/probe.AppImage" "$out" "$mode" 0) 2>"$work/err"
      fi
      status=$?
      printf '{"run":"%s","env":"%s","mode":"%s","place":"%s","program":"%s","status":%s}\n' \
        "$runname" "$envkind" "$mode" "$place" "$place/probe.AppImage" "$status" > "$outdir/$label--$runname.result"
      cat "$work/err" >> "$outdir/$label--$runname.result"
      echo "== $label $runname: status $status"
      cat "$work/err"
      [ -f "$out" ] && cat "$out"
    done
  done
fi
rm -rf "$work"
exit 0
