#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Gives a Windows job, after jdx/mise-action has installed mise.toml's
# Ruby and MSYS2 and exported their environment, what ruby/setup-ruby
# gave it beyond that environment, so that Ruby and the builds it runs
# see what they saw under setup-ruby:
#
#   windows-ruby-env.sh
#
# - TMPDIR, HOME, and MSYS2_PATH_TYPE, as setup-ruby's envPreInstall
#   exports them (index.js, at the v1.335.0 Fledge pinned). TMPDIR
#   matters most: without it Ruby's Dir.tmpdir is TMP, which on a runner
#   is C:\Users\RUNNER~1\..., and a build that hands such a path through
#   Shellwords to cmd.exe gets RUNNER\~1, which names nothing
#   (mini_portile's tar.xz extraction, which nokogiri's libxml2 takes).
# - MSYS2's usr/bin, behind its compiler's folder, and LANG from
#   MSYS2's locale, as `ridk enable` sets them (rubyinstaller2's
#   lib/ruby_installer/build/msys2_installation.rb, msys_apps_envvars, at
#   92a692c); mise.toml sets the rest of what ridk enable does.

set -eu

: "${MSYS2_PATH:?mise.toml sets no MSYS2_PATH}"
msys2=$(cygpath -u "$MSYS2_PATH")
locale=$("$msys2/usr/bin/locale" -uU)
case "$locale" in *UTF-8*) ;; *) locale=C ;; esac
mingw=$(cygpath -w "$msys2/${MSYSTEM_PREFIX:?mise.toml sets no MSYSTEM_PREFIX}/bin")

{
  echo "TMPDIR=$RUNNER_TEMP"
  echo "HOME=$USERPROFILE"
  echo "MSYS2_PATH_TYPE=inherit"
  echo "LANG=$locale"
} >> "$GITHUB_ENV"

# GITHUB_PATH puts each later line ahead of the earlier ones.
{
  cygpath -w "$msys2/usr/bin"
  echo "$mingw"
} >> "$GITHUB_PATH"
