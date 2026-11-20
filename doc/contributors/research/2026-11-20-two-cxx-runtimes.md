<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Findings of 2026-11-20 on whether an Android app with two copies of the C++ runtime behaves as a desktop does. Requested: written by an agent and not reviewed line by line. It changes no code and no ADR.
>
> What became of it: the same script, with each crossing's start written to the log by `/system/bin/log` and the head of the whole log printed, settled it the same day: crossing 0, the string, passed, and crossing 1 ended the app with "libc++abi: terminating due to uncaught exception of type St13runtime_error: boom", from `__cxa_throw` in `libc++_shared.so`, called by `thrower_raise` in `libthrower.so`, under the extension file. So the exception was the cause, as read below. Since then every C++ extension file and `libfledgeext.so` link `libc++_shared.so`, which the app carries stripped, and the gem answers each crossing on the emulator as on the desktop (`doc/contributors/design/phone-projects.md`, "One C++ runtime in an app"; `test/integration/mobile_extension_symbols_test.rb` runs the crossings on CI's emulators).

# Two C++ Runtimes in an Android App

An Android extension file and `libfledgeext.so` link the NDK's static C++ runtime and keep its symbols to themselves; a C++ library a gem's own build links takes the NDK's `libc++_shared.so`, which the app then carries (`doc/contributors/design/phone-projects.md`, "The C++ runtime rule" and "The NDK's shared C++ runtime"). An extension file that links such a library puts two copies of the runtime in one process, which the NDK warns against: "Exceptions raised in libfoo.so going uncaught in libbar.so, causing your app to crash" (developer.android.com/ndk/guides/cpp-support, "Static runtimes", last updated 2026-11-06). These runs looked for that in a Fledge app. Each ran on a Linux computer at `trunk` 5485ee81, with the Android runtime built at db1aefc2, on an x86_64 emulator of API 36.

## The gem

A path gem, `thrower`, whose `extconf.rb` first links `libthrower.so` from `ext/thrower/library/library.cc` with the `CXX` mkmf has (on the phone the NDK's clang++, over `libc++_shared.so`), then makes the extension from `ext/thrower/thrower.cc` alone, linked `-lthrower`. The extension calls the library seven ways: a `std::string` returned; a `std::runtime_error` the library throws, caught as `const std::exception &`; a `std::type_info` the library returns, compared by `==` and by address; `std::current_exception()` asked by the library inside the extension's `catch`; a terminate handler the library sets, read back with `std::get_terminate()`; a global locale the library sets, read by an `ostringstream`; and an `int` the library allocates and the extension deletes. The script below builds it, runs it under a Linux desktop's `ruby`, builds the Android app with `fledge build`, checks that the extension file leaves all seven of the library's functions undefined and defines none (so that each call crosses into `libthrower.so`), builds the debug and release APKs, and runs the app.

## What the runs showed

- **A first version proved nothing.** Its library's source sat in the extension's own folder, so mkmf compiled it into the extension too (`ORIG_SRCS = library.cc thrower.cc`), and the extension called its own copies. The app and a desktop agreed in every case, and nothing crossed. That build showed the extension file holding the static runtime with its state, `__cxa_get_globals`, `__cxa_begin_catch`, `__gxx_personality_v0`, the terminate handler, `std::locale`, `operator new` and `delete`, and the `std::exception` type_info, all local symbols, none in its dynamic table.
- **With the library apart, the desktop answers every case as one runtime does,** and the phone's app dies. On Linux: `greet=hello phone`, `caught=boom`, `same_type=true same_type_address=true`, `current_in_catch=true`, `terminate_seen=true`, `locale_number=1,5`, `deleted=7`. On the emulator, with all seven functions undefined in the extension file and defined in `libthrower.so` for both ABIs, the process ended "due to signal 6 (Aborted)", after the app wrote a memory map to the log, as Ruby's crash report ends with, and no line the program printed reached the log, though it prints and flushes a line before each crossing.
- **Which crossing aborts is not established.** The runs kept only the crash report's last lines, the memory map, and not its head, which names the signal's cause and the C backtrace. The same files had loaded and run in the first version, whose extension also needed `libthrower.so`, so a library not found is unlikely, though the second version's library is a different build. The NDK's words and the static runtime's local type_info point at the second crossing, the exception, which the extension's own personality routine would not match to its local `std::exception` and so leave to `std::terminate`; that is a reading, not an observation.
- **Gradle packs `libc++_shared.so` as Fledge copies it, unstripped,** in debug and release alike: 9,091,400 bytes for x86_64 and 9,485,032 for arm64-v8a, stored compressed as 2,713,929 and 2,733,832 in the debug APK and 2,411,821 and 2,416,192 in the release one. Stripped with the NDK's `llvm-strip --strip-unneeded` they are 1,390,752 and 1,423,696 bytes.

## What would settle it

The same run with the whole logcat kept as an artifact, or `adb logcat -d` printed whole after the abort: the head of Ruby's crash report or bionic's abort message (`libc: terminating due to uncaught exception of type ...`, if it is the exception) names the crossing. Running the crossings one per launch would name it too.

## The script

Run from a checkout of Fledge on Linux, with the Android SDK and NDK `bin/android-sdk` installs, an emulator `bin/android-emulator` can start, and the Android and x86_64-linux runtimes in `tmp/runtime` (`bundle exec rake runtime`), as `WORK=$(mktemp -d) bash crossing_proof2.sh`:

```sh
#!/usr/bin/env bash
# Five forms of C++ crossing between a C++ extension file and a C++
# shared library its extconf.rb links (libthrower.so, over the NDK's
# libc++_shared.so): a type_info compared, the current exception asked
# for inside a catch, a terminate handler set, a global locale set, and
# an allocation freed by the other side. Runs them first on this Linux
# desktop with plain ruby (one C++ runtime), then in an Android app
# fledge build makes at this commit, on an x86_64 emulator. Also prints
# what the NDK's libc++ says of type_info comparison, which C++ symbols
# the extension file exports, and the C++ runtime's size stripped and
# in the APK.
# Usage: WORK=FOLDER crossing_proof2.sh, with the runtimes in tmp/runtime
set -euo pipefail
: "${WORK:?a scratch folder}"
bin/setup
mise exec -- bin/android-sdk
ndk_bin=$(mise exec -- ruby -Ilib -rfledge -e 'puts Fledge::MobileExtensions::NDK.find(ENV, host: Fledge::Platform.local).bin')
app="$WORK/thrower_app"
gem="$app/thrower"
mkdir -p "$gem/ext/thrower/library" "$gem/lib"
cat > "$gem/ext/thrower/extconf.rb" <<'RUBY'
require "mkmf"
here = __dir__
system("#{RbConfig::CONFIG.fetch('CXX')} -shared -fPIC -o libthrower.so #{File.join(here, 'library', 'library.cc')}", exception: true)
$libs = "-L#{Dir.pwd} -lthrower #{$libs}"
create_makefile("thrower/thrower")
RUBY
cat > "$gem/ext/thrower/library/library.cc" <<'CXX'
#include <cstdlib>
#include <exception>
#include <locale>
#include <stdexcept>
#include <string>
#include <typeinfo>
std::string thrower_greet(const std::string &name) { return "hello " + name; }
void thrower_raise(const std::string &message) { throw std::runtime_error(message); }
const std::type_info &thrower_kind() { return typeid(std::runtime_error); }
bool thrower_has_current() { return static_cast<bool>(std::current_exception()); }
static void quiet_terminate() { std::abort(); }
void thrower_set_terminate() { std::set_terminate(quiet_terminate); }
struct comma : std::numpunct<char> { char do_decimal_point() const override { return ','; } };
void thrower_set_locale() { std::locale::global(std::locale(std::locale::classic(), new comma)); }
int *thrower_new() { return new int(7); }
CXX
cat > "$gem/ext/thrower/thrower.cc" <<'CXX'
#include <ruby.h>
#include <exception>
#include <sstream>
#include <stdexcept>
#include <string>
#include <typeinfo>
std::string thrower_greet(const std::string &name);
void thrower_raise(const std::string &message);
const std::type_info &thrower_kind();
bool thrower_has_current();
void thrower_set_terminate();
void thrower_set_locale();
int *thrower_new();
static std::string crossing(int which) {
  switch (which) {
  case 0: return "greet=" + thrower_greet("phone");
  case 1: try { thrower_raise("boom"); } catch (const std::exception &e) { return "caught=" + std::string(e.what()); } return "caught=nothing";
  case 2: return std::string("same_type=") + (thrower_kind() == typeid(std::runtime_error) ? "true" : "false") +
    " same_type_address=" + (&thrower_kind() == &typeid(std::runtime_error) ? "true" : "false");
  case 3: try { thrower_raise("again"); } catch (...) { return std::string("current_in_catch=") + (thrower_has_current() ? "true" : "false"); } return "current_in_catch=nothing";
  case 4: { std::terminate_handler before = std::get_terminate(); thrower_set_terminate();
    return std::string("terminate_seen=") + (std::get_terminate() != before ? "true" : "false"); }
  case 5: { thrower_set_locale(); std::ostringstream number; number << 1.5; return "locale_number=" + number.str(); }
  default: { int *seven = thrower_new(); int value = *seven; delete seven; return "deleted=" + std::to_string(value); }
  }
}
static VALUE cross(VALUE self, VALUE which) { return rb_str_new_cstr(crossing(NUM2INT(which)).c_str()); }
extern "C" void Init_thrower(void) {
  VALUE module = rb_define_module("Thrower");
  rb_define_module_function(module, "cross", RUBY_METHOD_FUNC(cross), 1);
}
CXX
printf 'require "thrower/thrower"\n' > "$gem/lib/thrower.rb"
cat > "$gem/thrower.gemspec" <<'RUBY'
Gem::Specification.new do |spec|
  spec.name = "thrower"
  spec.version = "1.0.0"
  spec.authors = ["Kerrick Long"]
  spec.summary = "A C++ extension over a C++ shared library its extconf.rb links"
  spec.files = %w[ext/thrower/extconf.rb ext/thrower/library/library.cc ext/thrower/thrower.cc lib/thrower.rb]
  spec.extensions = ["ext/thrower/extconf.rb"]
end
RUBY
printf 'source "https://rubygems.org"\ngem "thrower", path: "thrower"\n' > "$app/Gemfile"
cat > "$app/main.rb" <<'RUBY'
require "thrower"
7.times do |which|
  puts "Thrower: crossing #{which} starts"
  $stdout.flush
  puts "Thrower: crossing #{which}: #{Thrower.cross(which)} on #{RUBY_PLATFORM}"
  $stdout.flush
end
RUBY
printf 'name: ThrowerPhone\nidentifier: com.setdef.fledge.ThrowerPhone\n' > "$app/fledge.yml"

desk="$WORK/desktop"
mkdir -p "$desk"
echo "== desktop:"
if mise exec -- ruby -C "$desk" "$gem/ext/thrower/extconf.rb" >/dev/null && make -C "$desk" >/dev/null; then
  echo "desktop extension: $(nm -D --undefined-only "$desk/thrower.so" | grep -c '_Z[0-9]*thrower_') thrower_ functions undefined, $(nm -D --defined-only "$desk/thrower.so" | grep -c '_Z[0-9]*thrower_') defined; libthrower.so defines $(nm -D --defined-only "$desk/libthrower.so" | grep -c '_Z[0-9]*thrower_')"
  LD_LIBRARY_PATH="$desk" mise exec -- ruby -e 'require ARGV[0]; 7.times { |w| puts "Thrower: crossing #{w}: #{Thrower.cross(w)} on #{RUBY_PLATFORM}" }' "$desk/thrower.so" || echo "desktop run failed"
else
  echo "desktop build failed"
fi

BUNDLE_GEMFILE="$app/Gemfile" mise exec -- bundle lock --add-platform ruby --add-checksums >/dev/null
mise exec -- env FLEDGE_RUNTIME_DIR="$PWD/tmp/runtime" ruby -Ilib exe/fledge build android -o "$WORK/out" "$app"
project="$WORK/out/ThrowerPhone-android"
jni="$project/src/main/jniLibs"
for abi in x86_64 arm64-v8a; do
  ext="$jni/$abi/libfledgeext.thrower.thrower.so"
  und=$("$ndk_bin/llvm-readelf" --dyn-syms -W "$ext" | awk '$7=="UND"{print $8}' | grep -c '^_Z[0-9]*thrower_' || true)
  def=$("$ndk_bin/llvm-readelf" --dyn-syms -W "$ext" | awk '$7!="UND"{print $8}' | grep -c '^_Z[0-9]*thrower_' || true)
  lib=$("$ndk_bin/llvm-readelf" --dyn-syms -W "$jni/$abi/libthrower.so" | awk '$7!="UND"{print $8}' | grep -c '^_Z[0-9]*thrower_' || true)
  rt=$("$ndk_bin/llvm-readelf" --dyn-syms -W "$ext" | grep -cE ' (__cxa_get_globals|__cxa_begin_catch|__gxx_personality_v0|_ZSt13get_terminatev)$' || true)
  echo "== $abi crossing: the extension file has $und thrower_ functions undefined and $def defined, libthrower.so defines $lib; runtime state names in the extension's dynamic table: $rt; extension needs: $("$ndk_bin/llvm-readelf" --needed-libs "$ext" | grep -v Needed | tr -d '[] ' | tr '\n' ' ')"
  if [ "$und" -ne 7 ] || [ "$def" -ne 0 ] || [ "$lib" -ne 7 ]; then
    echo "== NOT A CROSSING: the extension does not call libthrower.so for all seven functions; stopping before the emulator"
    exit 3
  fi
done
for abi in x86_64 arm64-v8a; do
  cp "$jni/$abi/libc++_shared.so" "$WORK/stripped.so"
  "$ndk_bin/llvm-strip" --strip-unneeded "$WORK/stripped.so"
  echo "== $abi libc++_shared.so: $(wc -c < "$jni/$abi/libc++_shared.so") bytes as carried, $(wc -c < "$WORK/stripped.so") stripped, $(gzip -9c "$WORK/stripped.so" | wc -c) stripped and gzipped"
done
mise exec -- "$project/gradlew" --no-daemon -q --project-dir "$project" assembleDebug assembleRelease
for built in "$project"/build/outputs/apk/debug/*.apk "$project"/build/outputs/apk/release/*.apk; do
  echo "== $(basename "$built"), $(wc -c < "$built") bytes; libc++_shared.so in it (length, compressed, name):"
  unzip -v "$built" | awk '$NF ~ /libc\+\+_shared/ {print $1, $3, $NF}'
done
apk=$(ls "$project"/build/outputs/apk/debug/*-debug.apk)
cat > "$WORK/launch.rb" <<'RUBY'
require File.join(Dir.pwd, "tasks", "mobile_parity")
app = MobileParity::App.new(path: ARGV[1], name: "ThrowerPhone", identifier: "com.setdef.fledge.ThrowerPhone", prints: /Thrower/, phones: ["android"])
system("adb", "install", "-r", ARGV[0], exception: true)
begin
  logged = MobileParity::Android.new(work: ENV.fetch("WORK")).launch(app, timeout: 120)
  puts "== the app logged:", logged.entries
rescue => e
  puts "== the app did not finish; the error's last 60 lines:", e.message.lines.last(60)
  log = File.join(ENV.fetch("WORK"), "logcat-com.setdef.fledge.ThrowerPhone.txt")
  if File.exist?(log)
    puts "== logcat, crash reporters and the app's own lines:", File.readlines(log).grep(/ (DEBUG|libc|AndroidRuntime|linker|ruby|fledge|Fledge)\b|Thrower|terminat|abort|signal|dlopen|#\d\d pc/).last(60)
  else
    puts "== no logcat file at #{log}"
  end
end
RUBY
mise exec -- bin/android-emulator google_apis -- mise exec -- ruby "$WORK/launch.rb" "$apk" "$app"
```
