#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Keeps RubyInstaller's signed head build of the day each Ruby 4.1
# release appears (doc/contributors/design/runtimes.md, "Keeping
# RubyInstaller's head build"). RubyInstaller publishes Ruby 4.1 for
# Windows only as its rolling rubyinstaller-head release, whose files it
# replaces every night, and only that release's .asc files let a build
# be checked against RubyInstaller's key. So when the newest of the
# versions watched has appeared on cache.ruby-lang.org, and no
# pre-release named inputs-rubyinstaller-head-YYYYMMDD-for-VERSION in
# this repository keeps it yet, this downloads the four head files,
# checks both archives' signatures with gpgv against the key
# runtime/sources.yml pins for RubyInstaller, and publishes them
# unchanged on such a pre-release, then reads each back and checks its
# SHA-256. YYYYMMDD is the day RubyInstaller built the x64 archive, in
# UTC. The releases are the only state: once one is kept, later runs
# leave it alone, and none is ever overwritten or deleted.
#
# Only the newest release's day can still be kept, so an older version
# that was missed is not kept with a later build. A build older than the
# release's tarball is the night before's: the run fails, keeps
# nothing, and the next run tries again.
#
#   .github/scripts/keep-rubyinstaller-head.sh
#
# With DRY_RUN=1 it does everything but publish and read back, and
# prints the notes it would publish; so it runs on any computer with
# bash, curl, Ruby, gpg, and gpgv, and, to read each build's Ruby
# revision, 7-Zip. Publishing needs gh, logged in to this repository.
# The environment says the rest, with these defaults:
#
#   KEEP_VERSIONS           the versions watched, oldest first:
#                           4.1.0-preview2 4.1.0-preview3 4.1.0-rc1
#                           4.1.0-rc2 4.1.0
#   KEEP_RUBY_RELEASES_URL  https://cache.ruby-lang.org/pub/ruby/4.1
#   KEEP_HEAD_URL           RubyInstaller's rubyinstaller-head downloads
#   KEEP_SOURCES            runtime/sources.yml, whose Windows pins name
#                           the signing key
#   GITHUB_API_URL          https://api.github.com
#   GITHUB_REPOSITORY       setdef/Fledge, where the pre-releases go
#   GITHUB_SHA              the commit the pre-release's tag names:
#                           this checkout's HEAD
#   GITHUB_TOKEN            sent to GitHub's API when set
#   GITHUB_STEP_SUMMARY     where the notes are also written, when set
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
dry_run=${DRY_RUN:-}
read -r -a versions <<< "${KEEP_VERSIONS:-4.1.0-preview2 4.1.0-preview3 4.1.0-rc1 4.1.0-rc2 4.1.0}"
releases_url=${KEEP_RUBY_RELEASES_URL:-https://cache.ruby-lang.org/pub/ruby/4.1}
head_url=${KEEP_HEAD_URL:-https://github.com/oneclick/rubyinstaller2/releases/download/rubyinstaller-head}
sources=${KEEP_SOURCES:-$root/runtime/sources.yml}
api=${GITHUB_API_URL:-https://api.github.com}
repository=${GITHUB_REPOSITORY:-setdef/Fledge}
files=(rubyinstaller-head-x64.7z rubyinstaller-head-x64.7z.asc rubyinstaller-head-arm.7z rubyinstaller-head-arm.7z.asc)
archives=(rubyinstaller-head-x64.7z rubyinstaller-head-arm.7z)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

github() {
  local auth=()
  [ -z "${GITHUB_TOKEN:-}" ] || auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl -fsSL --retry 3 -H "Accept: application/vnd.github+json" ${auth[@]+"${auth[@]}"} "$api$1"
}

sha256() {
  if command -v sha256sum > /dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}

# The signing key both Windows pins name, which must be one key.
read -r key_url key_sha256 fingerprint < <(ruby -ryaml -e '
  keys = %w[x64-mingw-ucrt aarch64-mingw-ucrt].map do |platform|
    YAML.safe_load_file(ARGV[0], aliases: true).dig("ruby", "platforms", platform, "signature", "key") or abort "#{ARGV[0]} pins no signing key for #{platform}"
  end
  abort "#{ARGV[0]} pins two signing keys for RubyInstaller" unless keys.map { |key| key.slice("url", "sha256", "fingerprint") }.uniq.size == 1
  puts keys[0].values_at("url", "sha256", "fingerprint").join(" ")
' "$sources")
[ -n "$fingerprint" ] || fail "no signing key in $sources"

# The newest version watched that has appeared. A host that answers
# anything but found or not found fails the run, so that a release it
# hid is not passed over for an older one.
version=""
for candidate in "${versions[@]}"; do
  url="$releases_url/ruby-$candidate.tar.gz"
  code=$(curl -sS -I --retry 3 -o "$work/headers-$candidate" -w '%{http_code}' "$url" || true)
  case $code in
    200) version=$candidate ;;
    403 | 404) ;;
    *) fail "$url answered ${code:-nothing}" ;;
  esac
done
if [ -z "$version" ]; then
  echo "nothing new: none of ${versions[*]} has appeared at $releases_url"
  exit 0
fi
announced=$(tr -d '\r' < "$work/headers-$version" | sed -n 's/^[Ll]ast-[Mm]odified: *//p' | tail -n 1)
[ -n "$announced" ] || fail "$releases_url/ruby-$version.tar.gz has no Last-Modified, so a build cannot be judged against it"
echo "Ruby $version appeared at $announced"

# Kept already? The pre-releases are the only record.
page=1
while :; do
  github "/repos/$repository/releases?per_page=100&page=$page" > "$work/releases.json"
  kept=$(ruby -rjson -e '
    releases = JSON.parse(File.read(ARGV[0]))
    tag = releases.map { |release| release["tag_name"] }.grep(/\Ainputs-rubyinstaller-head-\d{8}-for-#{Regexp.escape(ARGV[1])}\z/).first
    puts(tag || (releases.size < 100 ? "" : "more"))
  ' "$work/releases.json" "$version")
  [ "$kept" = more ] || break
  page=$((page + 1))
done
if [ -n "$kept" ]; then
  echo "Ruby $version is already kept in $kept"
  exit 0
fi

# What RubyInstaller says of its head files: NAME SIZE UPDATED_AT each.
head_assets() {
  github "/repos/oneclick/rubyinstaller2/releases/tags/rubyinstaller-head" | ruby -rjson -e '
    assets = JSON.parse(STDIN.read).fetch("assets").to_h { |asset| [asset["name"], asset] }
    ARGV.each do |name|
      asset = assets[name] or abort "the rubyinstaller-head release has no #{name}"
      puts [name, asset["size"], asset["updated_at"]].join(" ")
    end
  ' "${files[@]}"
}
head_assets > "$work/assets-before"

# The stale-build guard: every file must be newer than the release.
ruby -rtime -e '
  announced = Time.httpdate(ARGV[0])
  stale = File.readlines(ARGV[1], chomp: true).map(&:split).select { |_, _, time| Time.iso8601(time) < announced }
  stale.each { |name, _, time| warn "error: #{name} was built at #{time}, before Ruby #{ARGV[2]} appeared at #{ARGV[0]}" }
  abort "error: RubyInstaller has no head build of that day yet; nothing is kept, and the next run tries again" unless stale.empty?
' "$announced" "$work/assets-before" "$version"

built=$(awk '$1 == "rubyinstaller-head-x64.7z" { print $3 }' "$work/assets-before")
day=${built%%T*}
tag="inputs-rubyinstaller-head-${day//-/}-for-$version"

# Download and verify, with the key checked against its pin first.
mkdir "$work/files"
curl -fsSL --retry 3 -o "$work/signing-key.asc" "$key_url"
echo "$key_sha256  $work/signing-key.asc" | sha256 -c - > /dev/null 2>&1 || fail "signing-key.asc does not match its pin in $sources"
mkdir -m 700 "$work/gnupg"
GNUPGHOME="$work/gnupg" gpg --batch --quiet --dearmor < "$work/signing-key.asc" > "$work/signing-key.gpg" 2> /dev/null ||
  fail "signing-key.asc is not a PGP key"
for name in "${files[@]}"; do
  curl -fsSL --retry 3 -o "$work/files/$name" "$head_url/$name" || fail "downloading $head_url/$name failed"
done
for name in "${archives[@]}"; do
  if gpgv --keyring "$work/signing-key.gpg" --status-fd 1 "$work/files/$name.asc" "$work/files/$name" 2> /dev/null |
    grep -q "^\[GNUPG:\] VALIDSIG $fingerprint "; then
    echo "$name: good signature from $fingerprint"
  else
    fail "$name is not signed by $fingerprint"
  fi
done

# The files must be the ones RubyInstaller described before the download.
head_assets > "$work/assets-after"
cmp -s "$work/assets-before" "$work/assets-after" || fail "RubyInstaller's head build changed while it was downloaded; the next run tries again"
while read -r name size _; do
  [ "$(wc -c < "$work/files/$name" | tr -d ' ')" = "$size" ] || fail "$name is not the size RubyInstaller reports"
done < "$work/assets-before"

# Each build's Ruby, from the RUBY_DESCRIPTION in its DLL, read without
# running it.
revision() {
  local seven dll description
  seven=$(command -v 7z || command -v 7zz || true)
  [ -n "$seven" ] || { echo "not read (no 7-Zip)"; return; }
  dll=$("$seven" l -slt "$1" 2> /dev/null | sed -n 's/^Path = \(.*\/bin\/[^/]*ruby[0-9]*\.dll\)$/\1/p' | head -n 1 || true)
  [ -n "$dll" ] || { echo "not read"; return; }
  # grep stops at the first match, and 7-Zip, cut off, fails: the match
  # is what counts.
  description=$("$seven" e -so "$1" "$dll" 2> /dev/null |
    LC_ALL=C grep -a -o -m 1 -E 'ruby [0-9]+\.[0-9]+\.[0-9]+[a-z0-9]* \([0-9-]+ [^)]*\)[ +A-Z]*\[[a-z0-9_-]+\]' || true)
  echo "${description:-not read}"
}

(cd "$work/files" && sha256 "${files[@]}") > "$work/SHA256SUMS"
{
  echo "Pinned inputs, not a Fledge release."
  echo
  echo "RubyInstaller publishes Ruby 4.1 for Windows only as its rolling \`rubyinstaller-head\` release, whose files are replaced every night. Ruby $version appeared at $releases_url/ruby-$version.tar.gz at $announced, and this release keeps RubyInstaller's head build of that day, unchanged, where Fledge's builds and anyone rebuilding them can still fetch it."
  echo
  echo "| File | SHA-256 | Updated at RubyInstaller |"
  echo "| --- | --- | --- |"
  while read -r name _ updated; do
    echo "| \`$name\` | \`$(awk -v name="$name" '$2 == name { print $1 }' "$work/SHA256SUMS")\` | $updated |"
  done < "$work/assets-before"
  echo
  for name in "${archives[@]}"; do
    echo "- \`$name\`: $(revision "$work/files/$name")"
  done
  echo
  echo "Each archive is signed by RubyInstaller's package signing key, fingerprint \`$fingerprint\`, which Fledge pins in \`runtime/sources.yml\` ($key_url). Check one with \`gpgv --keyring KEYRING FILE.asc FILE\`, the keyring being that key after \`gpg --dearmor\`. They are RubyInstaller's files (https://github.com/oneclick/rubyinstaller2), redistributed unchanged under their own licenses."
  if [ -n "${GITHUB_RUN_ID:-}" ]; then
    echo
    echo "Kept by ${GITHUB_SERVER_URL:-https://github.com}/$repository/actions/runs/$GITHUB_RUN_ID."
  fi
} > "$work/notes.md"
[ -z "${GITHUB_STEP_SUMMARY:-}" ] || cat "$work/notes.md" >> "$GITHUB_STEP_SUMMARY"

if [ -n "$dry_run" ]; then
  cat "$work/notes.md"
  echo
  echo "would keep $tag (dry run: nothing is published)"
  exit 0
fi

# gh release create would put a release on a tag that exists already,
# wherever it points, so such a tag is refused.
if github "/repos/$repository/git/ref/tags/$tag" > /dev/null 2>&1; then
  fail "the tag $tag exists already; nothing is overwritten"
fi
target=${GITHUB_SHA:-$(git -C "$root" rev-parse HEAD)}
gh release create "$tag" --repo "$repository" --prerelease --latest=false --target "$target" \
  --title "Pinned input: RubyInstaller head, $day, for Ruby $version" --notes-file "$work/notes.md" \
  "${files[@]/#/$work/files/}"

mkdir "$work/back"
gh release download "$tag" --repo "$repository" --dir "$work/back" "${files[@]/#/--pattern=}"
(cd "$work/back" && sha256 -c "$work/SHA256SUMS") || fail "a file read back from $tag does not match what was published"
echo "kept $tag"
