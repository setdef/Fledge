# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Spike (throwaway): every external input the mobile spike builds from,
# pinned by version and SHA-256, and a fetch helper that refuses a
# download whose hash differs. Sourced by ios/ and android/ scripts.

RUBY_VERSION=4.0.9
RUBY_URL=https://cache.ruby-lang.org/pub/ruby/4.0/ruby-4.0.9.tar.gz
RUBY_SHA256=c35350682ff050b79702d57ade4516e7336063f510155d19fb2fb5b3f3909511

# OpenSSL 3.6.3 (Apache-2.0), the release xord/cruby's config.rb pins.
OPENSSL_URL=https://github.com/openssl/openssl/releases/download/openssl-3.6.3/openssl-3.6.3.tar.gz
OPENSSL_SHA256=243a86649cf6f23eeb6a2ff2456e09e5d77dd9018a54d3d96b0c6bdd6ba6c7f1

# libyaml 0.2.5 (MIT), for psych.
YAML_URL=https://github.com/yaml/libyaml/releases/download/0.2.5/yaml-0.2.5.tar.gz
YAML_SHA256=c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4

# libffi 3.5.2 (MIT), for fiddle on Android only (iOS leaves fiddle out).
FFI_URL=https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz
FFI_SHA256=f3a3082a23b37c293a4fcd1053147b371f2ff91fa7ea1b2a52e335676bac82dc

# Android NDK r30 (the latest stable on 2026-10-27; r28+ aligns ELF
# segments to 16 KB by default).
NDK_VERSION=r30
NDK_LINUX_URL=https://dl.google.com/android/repository/android-ndk-r30-linux.zip
NDK_LINUX_SHA256=753611f410d002cfcd3f3dc2ef49aad532089d3180b436c060a90bf0fcb64df2
NDK_DARWIN_URL=https://dl.google.com/android/repository/android-ndk-r30-darwin.zip
NDK_DARWIN_SHA256=d125634de97b26deb1e1bb1a562f9d839aa5803d1784a1e414485f5ccbe6739f

SPIKE_CACHE=${SPIKE_CACHE:-$HOME/.cache/fledge-spike-mobile}

fetch() { # url sha256 -> prints the cached path
  local url=$1 sha=$2 file
  file="$SPIKE_CACHE/$(basename "$url")"
  mkdir -p "$SPIKE_CACHE"
  if [ ! -f "$file" ]; then
    curl -sSfL -o "$file.part" "$url" && mv "$file.part" "$file"
  fi
  local got
  got=$(shasum -a 256 "$file" 2>/dev/null | cut -d' ' -f1 || sha256sum "$file" | cut -d' ' -f1)
  if [ "$got" != "$sha" ]; then
    echo "SHA-256 mismatch for $url: expected $sha, got $got" >&2
    return 1
  fi
  echo "$file"
}

ncpu() { getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4; }
