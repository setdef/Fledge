#!/usr/bin/env bash
# winacp: what activeCodePage changes in Fledge's console and windowed
# launchers, against the runtime's own ruby.exe and rubyw.exe, and
# whether a manifest file beside a copy of ruby.exe takes effect. An
# experiment's facts, not a check.
set -u
W=$(cygpath -m "${RUNNER_TEMP:-$TEMP}")/winacp
D="$W/héllo wörld"
mkdir -p "$D"
for kind in console windowed; do
  mkdir -p "$W/src/$kind"; cp winacp/app/main.rb "$W/src/$kind/"
  printf 'name: Acp%s\nkind: %s\nidentifier: com.setdef.fledge.Acp%s\n' "$kind" "$kind" "$kind" > "$W/src/$kind/fledge.yml"
  bundle exec ruby exe/fledge build -o "$W/dist" "$W/src/$kind" 2>&1 | tail -3
done
for z in "$W"/dist/*.zip; do /c/Windows/System32/tar.exe -xf - -C "$D" < "$z"; done
ls "$D"
C=$(ls -d "$D"/Acpconsole-*/ | head -1); G=$(ls -d "$D"/Acpwindowed-*/ | head -1)
echo "== chcp: $(/c/Windows/System32/chcp.com)"
export WINACP="ünï"
echo "== console launcher"; "$C"Acpconsole.exe "" "$D"
echo "== runtime ruby.exe main.rb"; "$C"ruby/bin/ruby.exe "$C"app/main.rb "" "$D"
echo "== TZ=CET-1: launcher, then ruby.exe"
TZ=CET-1 "$C"Acpconsole.exe "" "$D" | grep Time
TZ=CET-1 "$C"ruby/bin/ruby.exe "$C"app/main.rb "" "$D" | grep Time
echo "== chcp 437: launcher, then ruby.exe"
/c/Windows/System32/chcp.com 437 > /dev/null
"$C"Acpconsole.exe "" "$D" | grep -i "cp\|locale\|Encoding"
"$C"ruby/bin/ruby.exe "$C"app/main.rb "" "$D" | grep -i "cp\|locale\|Encoding"
/c/Windows/System32/chcp.com 65001 > /dev/null
win=$(ls "$G"*.exe | head -1)
echo "== windowed launcher $win"
"$win" "$W/gui.txt" "$D"; sleep 5; cat "$W/gui.txt"
echo "== rubyw.exe main.rb"
"$G"ruby/bin/rubyw.exe "$G"app/main.rb "$W/rubyw.txt" "$D"; sleep 5; cat "$W/rubyw.txt"
echo "== a copy of ruby.exe with a manifest file beside it"
B="$C"ruby/bin
cp "$B/ruby.exe" "$B/rubyacp.exe"
cat > "$B/rubyacp.exe.manifest" <<'XML'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <activeCodePage xmlns="http://schemas.microsoft.com/SMI/2019/WindowsSettings">UTF-8</activeCodePage>
    </windowsSettings>
  </application>
</assembly>
XML
"$B/rubyacp.exe" "$C"app/main.rb "" "$D" | grep "GetACP\|setlocale"
echo "== ruby.exe's embedded manifest"
"$B/ruby.exe" -e 'b = File.binread(ARGV[0]); i = b.index("<assembly"); puts(i ? b[i, 1500].scrub : "none")' "$B/ruby.exe"
exit 0
