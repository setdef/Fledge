# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Spike (throwaway): source changes both mobile builds make to Ruby 4.0.9.
#
# Ruby's build never links a bundled gem's C extension statically:
# template/configure-ext.mk.tmpl passes --no-extstatic for .bundle/gems,
# and ext/extmk.rb (line 656) calls extmake(d, ext_prefix, !@gemname),
# so a gem's extension is never put in extinit.c. With no dynamic
# loading (iOS) the gem's .bundle cannot even link. xord/cruby (Rakefile
# lines 348-390) moves every bundled gem into the standard library; this
# moves only the ones with C extensions, as ordinary ext/ extensions,
# with their Ruby files in lib/, and drops them from gems/bundled_gems.
# Cost: they stop being gems (no specification, Gem.loaded_specs lacks
# them), which FINDINGS.md weighs against decision 9.
#
#   absorb_bundled_c_gems SRC "fiddle ..."   (gems to leave out entirely)
absorb_bundled_c_gems() {
  # xord/cruby (Rakefile lines 312-317): psych's extconf.rb prefers
  # pkg-config's yaml-0.1, the build machine's, over --with-libyaml-dir
  # (Homebrew's leaked into the Android link here). Configure also gets
  # PKG_CONFIG=false, so no extension finds the build machine's libraries.
  perl -pi -e "s/elsif\\s+pkg_config\\(['\"]yaml-[\\d.]+['\"]\\)/elsif false/" "$1/ext/psych/extconf.rb"
  grep -q 'elsif false' "$1/ext/psych/extconf.rb"

  local src=$1 omit=" $2 " d gem name
  for d in "$src"/.bundle/gems/*/; do
    gem=$(basename "$d"); name=${gem%-*}
    [ -d "$d/ext" ] || continue
    [ "$name" = win32ole ] && continue
    sed -i.bak -E "/^$name /d" "$src/gems/bundled_gems"
    rm -f "$src/gems/$gem.gem"
    if [[ $omit != *" $name "* ]]; then
      for e in "$d"ext/*/; do
        [ "$(basename "$e")" = java ] && continue
        cp -R "$e" "$src/ext/$(basename "$e")"
      done
      cp -R "$d"lib/. "$src/lib/"
      echo "absorbed bundled gem $gem into ext/ and lib/"
    else
      echo "left out bundled gem $gem"
    fi
    rm -rf "$d" "$src"/.bundle/specifications/"$gem".gemspec
  done
}

# A cross-compiled CRuby has no builtin binary: configure.ac (lines
# 1584-1588 at 4.0.9) sets X_BUILTIN_BINARY=no when cross compiling,
# since only miniruby can write it, so builtin.c falls back to
# mini_builtin.c, whose Init_builtin_features never loads gem_prelude:
# such a Ruby boots with no RubyGems, did_you_mean, error_highlight, or
# syntax_suggest, and compiles its builtins from source on every boot.
# An iseq binary depends only on Ruby's version, endianness, and word
# size (compile.c, ibf_load_setup_bytes), so a miniruby built for the
# build machine from the same source and options writes the same one.
#
#   build_host_miniruby SRC DEST     -> DEST/miniruby
#   use_host_builtin_binary BUILD SRC HOST_MINIRUBY_DIR
build_host_miniruby() {
  local src=$1 dest=$2
  [ -x "$dest/miniruby" ] && return 0
  mkdir -p "$dest"
  (unset IPHONEOS_DEPLOYMENT_TARGET CC CFLAGS CPPFLAGS LDFLAGS; cd "$dest" && "$src/configure" -q --disable-shared --disable-yjit --disable-zjit \
     --disable-install-doc --with-baseruby="$(command -v ruby)" >/dev/null &&
   make -s -j"$(ncpu)" miniruby >/dev/null 2>&1)
  [ -x "$dest/miniruby" ]
}
use_host_builtin_binary() {
  local build=$1 src=$2 host=$3
  (cd "$host" && ./miniruby -I"$src/lib" -I. -I.ext/common "$src/tool/generic_erb.rb" \
     -o "$build/builtin_binary.rbbin" "$src/template/builtin_binary.rbbin.tmpl")
  grep -q BUILTIN_BINARY_SIZE "$build/builtin_binary.rbbin"
  # Keep make from replacing it with the empty cross-compiling stub: a
  # rule after GNUmakefile's includes overrides common.mk's recipe.
  sed -i.bak -e 's/^BUILTIN_BINARY = no/BUILTIN_BINARY = yes/' "$build/Makefile"
  printf '\nbuiltin_binary.rbbin: ; @:\n' >> "$build/GNUmakefile"
}
