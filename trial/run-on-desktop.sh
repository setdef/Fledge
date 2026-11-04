#!/bin/sh
# Runs the Lota trial's built app on a computer with no Ruby, in stages:
# bare (no display), Xvfb alone, then the libraries a desktop has, then
# the .deb and the AppImage. Every stage records its output and goes on.
#
#   run-on-desktop.sh DIST PLATFORM
set -u

dist=$(cd "$1" && pwd)
platform=$2
results=${RESULTS:-$PWD/results}
mkdir -p "$results"
export DEBIAN_FRONTEND=noninteractive

section() { printf '\n========== %s ==========\n' "$*"; }

# run LABEL CMD...: runs CMD for at most 40 s, saves its output, and
# prints it with the exit status.
run() {
  label=$1
  shift
  section "run: $label"
  timeout 40 "$@" >"$results/$label.out" 2>"$results/$label.err"
  status=$?
  echo "exit status: $status"
  echo "--- stdout (last 30 lines)"
  tail -n 30 "$results/$label.out"
  echo "--- stderr (last 40 lines)"
  tail -n 40 "$results/$label.err"
  echo "$label $status" >>"$results/statuses.txt"
}

packages() { dpkg-query -W -f '${Package}\n' | sort >"$results/packages-$1.txt"; }

# dlopens LABEL: runs the program under Xvfb with LD_DEBUG=libs, and
# lists the libraries the dynamic loader looked for (at startup and by
# dlopen) and those it found nowhere on this computer.
dlopens() {
  label=$1
  rm -f "$results/ld-$label".*
  xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 LD_DEBUG=libs LD_DEBUG_OUTPUT="$results/ld-$label" timeout 40 "$program" >/dev/null 2>&1
  section "dlopen search ($label)"
  cat "$results/ld-$label".* 2>/dev/null >"$results/ld-$label.log"
  sed -n 's/.*find library=\([^ ;]*\).*/\1/p' "$results/ld-$label.log" | sort -u >"$results/searched-$label.txt"
  sed -n 's/.*trying file=\(.*\)/\1/p' "$results/ld-$label.log" | sort -u >"$results/tried-$label.txt"
  echo "libraries searched for:"
  tr '\n' ' ' <"$results/searched-$label.txt"
  echo
  echo "searched for and found nowhere:"
  : >"$results/missing-$label.txt"
  while read -r lib; do
    found=no
    for f in $(grep "/$lib\$" "$results/tried-$label.txt"); do [ -e "$f" ] && found=yes; done
    [ "$found" = yes ] || echo "$lib" >>"$results/missing-$label.txt"
  done <"$results/searched-$label.txt"
  sed 's/^/  /' "$results/missing-$label.txt"
}

section "computer"
cat /etc/os-release
ldd --version | head -1
uname -m
echo "LANG=${LANG-} LC_ALL=${LC_ALL-}"
locale 2>&1 || true
if command -v ruby; then echo "ruby is on PATH: this is not a computer with no Ruby"; exit 1; fi
echo "no ruby on PATH"

apt-get update -qq
packages bare

work=/opt/trial
mkdir -p "$work"
tar -xzf "$dist/LotaTrial-$platform.tar.gz" -C "$work"
app="$work/LotaTrial-$platform"
section "the app's folder"
find "$app" -maxdepth 2 | sort | head -40
program="$app/LotaTrial"
[ -x "$program" ] || { echo "no program at $program"; ls -la "$app"; exit 1; }
native=$(find "$app" -path '*lota*' -name native.so | head -1)
echo "native extension: $native"

section "ldd of the native extension and its bundled libraries (bare)"
ldd "$native"
for lib in "$(dirname "$native")"/libraries/*; do echo "-- $lib"; ldd "$lib"; done
section "ldd of the program"
ldd "$program"

run bare-no-display "$program"

section "install Xvfb alone (--no-install-recommends)"
apt-get install -y -qq --no-install-recommends xvfb xauth >/dev/null
packages xvfb
comm -13 "$results/packages-bare.txt" "$results/packages-xvfb.txt" | tr '\n' ' '
echo
run xvfb-only xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 "$program"
dlopens xvfb-only

section "install a desktop's libraries: X11, Wayland, Mesa, ALSA, PulseAudio"
apt-get install -y -qq --no-install-recommends \
  libgl1 libegl1 libgl1-mesa-dri libglx-mesa0 libegl-mesa0 \
  libx11-6 libxext6 libxcursor1 libxi6 libxrandr2 libxss1 libxfixes3 libxkbcommon0 libxtst6 \
  libwayland-client0 libwayland-cursor0 libwayland-egl1 libdecor-0-0 \
  libasound2t64 libpulse0 libdbus-1-3 libudev1 >/dev/null
packages desktop
comm -13 "$results/packages-xvfb.txt" "$results/packages-desktop.txt" | tr '\n' ' '
echo
run desktop-xvfb xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 "$program"
dlopens desktop-xvfb
run desktop-xvfb-dummy-audio xvfb-run -a -s "-screen 0 1024x768x24" env LIBGL_ALWAYS_SOFTWARE=1 SDL_AUDIODRIVER=dummy "$program"

section "ldd of the native extension and its bundled libraries (desktop)"
ldd "$native"

if [ -f "$dist/LotaTrial-$platform.deb" ]; then
  deb="$dist/LotaTrial-$platform.deb"
  section ".deb fields"
  dpkg-deb --info "$deb"
  package=$(dpkg-deb --field "$deb" Package)
  apt-get install -y -qq "$deb" >"$results/apt-deb.out" 2>&1
  echo "apt install status: $?"
  tail -5 "$results/apt-deb.out"
  dpkg -L "$package" | head -30
  run deb-xvfb xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 "/usr/lib/$package/LotaTrial"
  apt-get remove -y -qq "$package" >/dev/null
  echo "removed $package"
fi

if [ -f "$dist/LotaTrial-$platform.AppImage" ]; then
  image=/opt/LotaTrial.AppImage
  cp "$dist/LotaTrial-$platform.AppImage" "$image"
  chmod +x "$image"
  run appimage-no-fuse xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 "$image"
  run appimage-extract-and-run xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 APPIMAGE_EXTRACT_AND_RUN=1 "$image"
fi

section "statuses"
cat "$results/statuses.txt"
