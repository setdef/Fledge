#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of a windowed app on macOS and Linux:
# unpacks what fledge build wrote for test/fixtures/windowed_app, checks the
# identity each operating system reads with that system's own tools, and
# starts the app the way the system would, with no Ruby anywhere it can
# reach.
#
#   deliver-windowed.sh ARCHIVE
#
# ARCHIVE is "Hello Window-PLATFORM.tar.gz". On macOS the app is an .app
# bundle: codesign must verify it strictly and deeply, plutil must read
# what fledge.yml says from its Info.plist, the files and folders it
# opens among it, which Launch Services must then offer it for, and it
# must run both through open -W, as Finder starts it, and through its
# own program, and open -a with a document, as Finder's double-click on
# one starts it, must give its program that document's path. On Linux it is a folder with a desktop entry, which
# desktop-file-validate must accept, with the MIME types of what it
# opens, and icons in the hicolor theme's folders. The app writes a
# report of what it ran on to the path it is given, and exits with the
# status it is given.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

archive=$1
name="Hello Window"
identifier=com.setdef.fledge.HelloWindow
version=1.2.3

fail() {
  echo "::error::Delivery (windowed): $*" >&2
  exit 1
}

# expect LABEL ACTUAL EXPECTED
expect() {
  [ "$2" = "$3" ] || fail "$1 is '$2', not '$3'"
  echo "ok: $1 is $3"
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
archive=$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")
folder=$(basename "$archive" .tar.gz)
place="$work/My Apps/Ünïcödé 日本"
mkdir -p "$place"
tar -xzf "$archive" -C "$place"
root="$place/$folder"

empty="$work/empty-path"
mkdir -p "$empty"
if env -i PATH="$empty" /bin/sh -c 'command -v ruby' >/dev/null 2>&1; then
  fail "ruby is still reachable on the app's PATH"
fi

# run_report LABEL STATUS PROGRAM: runs PROGRAM from / in an empty
# environment, and fails unless it exits with STATUS and its report says
# it ran this runtime's Ruby, from the app's own folder.
run_report() {
  report="$work/report-$1.json"
  set +e
  (cd / && env -i PATH="$empty" HOME="$work" "$3" "$report" "$2") >"$work/out" 2>"$work/err"
  actual=$?
  set -e
  [ "$actual" -eq "$2" ] || { cat "$work/out" "$work/err"; fail "$1: exit status $actual, not $2"; }
  [ ! -s "$work/err" ] || { cat "$work/err"; fail "$1: it wrote to standard error"; }
  check_report "$1" "$report"
}

# check_report LABEL REPORT
check_report() {
  grep -q '"ruby":"4.1.0"' "$2" || fail "$1: the report says another Ruby: $(cat "$2")"
  grep -q '"program":"main.rb","folder":"app"' "$2" || fail "$1: the report says another program: $(cat "$2")"
  echo "ok: $1 ran and reported $(cat "$2")"
}

case "$(uname -s)" in
  Darwin)
    bundle="$root/$name.app"
    plist="$bundle/Contents/Info.plist"
    [ -d "$bundle" ] || fail "there is no $name.app in $folder"
    codesign --verify --strict --deep --verbose=2 "$bundle" || fail "codesign does not verify $name.app"
    codesign --display --verbose=2 "$bundle" 2>&1 | grep -qx "Identifier=$identifier" || fail "the signature does not name $identifier"
    echo "ok: codesign verifies $name.app, strictly and deeply, signed for $identifier"
    expect CFBundleIdentifier "$(plutil -extract CFBundleIdentifier raw "$plist")" "$identifier"
    expect CFBundleName "$(plutil -extract CFBundleName raw "$plist")" "$name"
    expect CFBundleDisplayName "$(plutil -extract CFBundleDisplayName raw "$plist")" "$name"
    expect CFBundleExecutable "$(plutil -extract CFBundleExecutable raw "$plist")" "$name"
    expect CFBundleShortVersionString "$(plutil -extract CFBundleShortVersionString raw "$plist")" "$version"
    expect CFBundleVersion "$(plutil -extract CFBundleVersion raw "$plist")" 1.2.417
    expect CFBundlePackageType "$(plutil -extract CFBundlePackageType raw "$plist")" APPL
    expect LSMinimumSystemVersion "$(plutil -extract LSMinimumSystemVersion raw "$plist")" 26.0
    expect NSHighResolutionCapable "$(plutil -extract NSHighResolutionCapable raw "$plist")" true
    expect NSHumanReadableCopyright "$(plutil -extract NSHumanReadableCopyright raw "$plist")" "© 2026 setdef"
    icon="$bundle/Contents/Resources/$(plutil -extract CFBundleIconFile raw "$plist")"
    expect "the icon's width" "$(sips -g pixelWidth "$icon" | sed -n 's/^ *pixelWidth: //p')" 1024
    grep -q "^This app was built with Fledge" "$bundle/Contents/Resources/notices/NOTICES.txt" || fail "the app has no notices"
    # What it opens (file_associations;
    # doc/contributors/design/desktop-apps.md, "Files an app opens"): document
    # types ranked Alternate, read back by plutil, and then by Launch
    # Services itself, which, once the bundle is registered, must offer
    # the app for a folder and for a report, as Finder's "Open With" does.
    types="CFBundleDocumentTypes"
    expect "the folders' content type" "$(plutil -extract "$types.0.LSItemContentTypes.0" raw "$plist")" public.folder
    expect "the folders' role" "$(plutil -extract "$types.0.CFBundleTypeRole" raw "$plist")" Viewer
    expect "the folders' rank" "$(plutil -extract "$types.0.LSHandlerRank" raw "$plist")" Alternate
    expect "the reports' name" "$(plutil -extract "$types.1.CFBundleTypeName" raw "$plist")" "Hello Window report"
    expect "the reports' extension" "$(plutil -extract "$types.1.CFBundleTypeExtensions.0" raw "$plist")" hellowindow
    expect "the reports' role" "$(plutil -extract "$types.1.CFBundleTypeRole" raw "$plist")" Editor
    # Launch Services leaves out an app in a temporary folder, such as
    # mktemp's under /var/folders, so a copy goes in the home folder,
    # where a person keeps one.
    lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    kept="$HOME/Fledge Delivery $$"
    mkdir -p "$kept/Ein Ordner ü"
    ditto "$bundle" "$kept/$name.app"
    "$lsregister" -f "$kept/$name.app"
    sleep 2
    : >"$kept/dropped.hellowindow"
    for target in "$kept/Ein Ordner ü" "$kept/dropped.hellowindow"; do
      apps=$(osascript -l JavaScript -e 'ObjC.import("AppKit")' -e 'function run(argv) {
        const urls = $.NSWorkspace.sharedWorkspace.URLsForApplicationsToOpenURL($.NSURL.fileURLWithPath(argv[0]));
        const paths = [];
        for (let i = 0; i < urls.count; i++) paths.push(urls.objectAtIndex(i).path.js);
        return paths.join("\n");
      }' "$target")
      printf '%s\n' "$apps" | grep -q "/$name.app\$" || { printf '%s\n' "$apps"; fail "Launch Services does not offer $name.app for $target"; }
      echo "ok: Launch Services offers $name.app for $(basename "$target")"
    done
    "$lsregister" -u "$kept/$name.app"
    rm -rf "$kept"

    run_report "its own program" 4 "$bundle/Contents/MacOS/$name"
    # open -W starts the app as Finder does, through Launch Services, and
    # waits for it to quit; it does not pass the app's exit status on.
    report="$work/report-open.json"
    open -n -W "$bundle" --args "$report" 4 || fail "open could not start $name.app"
    check_report "open -W" "$report"
    # open -a APP DOCUMENT is what a double-click on a document in Finder
    # sends: Launch Services starts the app and hands it the document in
    # an Open Documents Apple event, which the launcher gives the program
    # as an argument (doc/contributors/design/launcher.md, "Documents
    # opened on macOS"). The app writes its report over the document it
    # is given, so an empty document means the program never saw it.
    opened="$work/Geöffnet ☃.hellowindow"
    : >"$opened"
    open -n -W -a "$bundle" "$opened" || fail "open could not start $name.app with a document"
    [ -s "$opened" ] || fail "open -a: the program was not given the document it was opened with"
    grep -q '"arguments":1,' "$opened" || fail "open -a: the program was given other arguments: $(cat "$opened")"
    check_report "open -a with a document" "$opened"
    # Given arguments as well, the program sees them first and the
    # document after them, as ruby main.rb ARGS DOCUMENT would.
    : >"$opened"
    report="$work/report-open-both.json"
    open -n -W -a "$bundle" "$opened" --args "$report" 0 || fail "open could not start $name.app with a document and arguments"
    grep -q '"arguments":3,' "$report" || fail "open -a with arguments: the program was given other arguments: $(cat "$report" 2>/dev/null)"
    check_report "open -a with a document and arguments" "$report"
    ;;
  Linux)
    program="$root/$name"
    desktop="$root/$identifier.desktop"
    [ -x "$program" ] || fail "$name is not executable after unpacking"
    desktop-file-validate "$desktop" || fail "desktop-file-validate rejects $identifier.desktop"
    echo "ok: desktop-file-validate accepts $identifier.desktop"
    expect Name "$(sed -n 's/^Name=//p' "$desktop")" "$name"
    expect Comment "$(sed -n 's/^Comment=//p' "$desktop")" "Says hello from a window"
    expect Exec "$(sed -n 's/^Exec=//p' "$desktop")" "\"$name\" %F"
    expect MimeType "$(sed -n 's/^MimeType=//p' "$desktop")" "inode/directory;application/x-hellowindow;"
    expect Icon "$(sed -n 's/^Icon=//p' "$desktop")" "$identifier"
    expect Terminal "$(sed -n 's/^Terminal=//p' "$desktop")" false
    for size in 16 32 64 128 256 512; do
      icon="$root/share/icons/hicolor/${size}x$size/apps/$identifier.png"
      file "$icon" | grep -q "PNG image data, $size x $size" || fail "$icon is not a $size-pixel PNG: $(file "$icon")"
    done
    echo "ok: the hicolor theme's folders hold the icon at every size"
    types="$root/share/mime/packages/$identifier.xml"
    grep -qF '<mime-type type="application/x-hellowindow">' "$types" || fail "$types does not define application/x-hellowindow"
    grep -qF '<glob pattern="*.hellowindow"/>' "$types" || fail "$types does not give the type *.hellowindow"
    echo "ok: share/mime/packages defines the reports' type, application/x-hellowindow"
    grep -q "^This app was built with Fledge" "$root/notices/NOTICES.txt" || fail "the app has no notices"
    run_report "its program" 4 "$program"
    ;;
  *) fail "no windowed delivery for $(uname -s)" ;;
esac

echo "Delivered: $name, windowed"
