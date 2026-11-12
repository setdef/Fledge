<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: an ffi bug report, for the maintainer to file

Not filed. For the maintainer to file, if he chooses, at https://github.com/ffi/ffi/issues/new, with the title below, and everything after the line as the body (GitHub takes Markdown).

ffi's issue template asks for the ffi version, the Ruby version and platform, and a reproduction. Before filing: search ffi's issues and pull requests for "LoadLibraryExA", "LoadLibraryW", and "non-ASCII", since someone may have reported it after 2026-11-12 (nothing matched on that day); and read the body start to finish as your own words, since you are the one filing it. Found when `examples/native_app` began to ship the libusb gem's Windows build and Fledge's Delivery, which unpacks every app under a folder whose name is not ASCII, could not load its DLL (CI run 43237130653, job "Delivery from source (x64-mingw-ucrt)"). The reproduction below ran on a Windows 11 PC with RubyInstaller's own `ruby.exe`, not Fledge's; the suggested fix has not been compiled or run.

- **Title:** Windows: `ffi_lib` cannot open a DLL whose path is not ASCII (`LoadLibraryExA` reads Ruby's UTF-8 path in the ANSI code page)

---

On Windows, `FFI::DynamicLibrary.open` (and with it `ffi_lib`) fails with error 126, "The specified module could not be found", for a DLL that exists, whenever the DLL's path holds a character outside ASCII and the process's ANSI code page is not UTF-8, which is every Windows install that has not turned on the "Beta: Use Unicode UTF-8" setting. A gem that carries its own DLL and finds it from `__dir__`, such as libusb's `x64-mingw-ucrt` build, then cannot load at all when it is installed under `C:\Users\José\...`, or in a project folder named `Müller`.

## Cause

`library_initialize` passes the Ruby string's bytes to `dl_open` as they are (`ext/ffi_c/DynamicLibrary.c`, line 147 at v1.17.4 and at master 5b8870c4f9), and on Windows `dl_open` calls the ANSI functions (lines 215 to 225):

```c
static void*
dl_open(const char* name, int flags)
{
    if (name == NULL) {
        return GetModuleHandle(NULL);
    } else {
        DWORD dwFlags = PathIsRelativeA(name) ? 0 : LOAD_WITH_ALTERED_SEARCH_PATH;
        return LoadLibraryExA(name, NULL, dwFlags);
    }
}
```

Ruby's strings for paths on Windows are UTF-8: `Encoding.find("filesystem")` is UTF-8 there, so `__dir__`, `File.expand_path` and `Dir.glob` all give UTF-8. `LoadLibraryExA` reads its argument in the ANSI code page instead (`GetACP()`, 1252 on an English Windows), so `é`, the bytes `C3 A9`, becomes `Ã©`, and Windows looks for a file that does not exist.

Ruby loads its own extensions the other way: `dln_open` converts the path from UTF-8 and calls the wide function (`dln.c`, lines 337 to 343 at ruby/ruby 0e25874222):

```c
    WCHAR *winfile = rb_w32_mbstr_to_wstr(CP_UTF8, file, -1, NULL);
    ...
    handle = LoadLibraryW(winfile);
```

which is why `require "ffi"` succeeds from the same folder and only the DLL ffi opens fails.

A second, smaller effect: `dl_error` formats the message with `FormatMessageA`, and the `LoadError`'s message comes out as ASCII-8BIT holding the UTF-8 path's bytes. When nothing rescues it, Ruby prints the backtrace's first line and then nothing at all, so the person sees an empty message.

## Reproduction

ruby 4.1.0dev (2026-11-10 master 0e25874222) +PRISM [x64-mingw-ucrt], RubyInstaller's head build, ffi 1.17.4 compiled from source, libusb 0.8.0 (`x64-mingw-ucrt`), Windows 11 with the ANSI code page 1252. A project whose `Gemfile` holds only `gem "libusb"`, installed with `bundle install` into `vendor/bundle`, with this `main.rb`:

```ruby
require "libusb"
puts "loaded libusb #{LIBUSB.version}"
```

Run from `C:\...\ascii\libusb_probe`:

```
> bundle exec ruby main.rb
loaded libusb 1.0.30
```

The same folder, copied to `C:\...\héllo wörld\libusb_probe`:

```
> bundle exec ruby main.rb
C:/.../héllo wörld/libusb_probe/vendor/bundle/ruby/4.1.0+6/gems/ffi-1.17.4/lib/ffi/dynamic_library.rb:94:in 'FFI::DynamicLibrary.load_library': 
```

The message, rescued and inspected, is ASCII-8BIT:

```
Could not open library 'C:/.../h\xC3\xA9llo w\xC3\xB6rld/libusb_probe/vendor/bundle/ruby/4.1.0+6/gems/libusb-0.8.0-x64-mingw-ucrt/lib/libusb-1.0.dll': Failed with error 126: The specified module could not be found.\r\n.\n...
```

## Suggested fix

Convert the name to UTF-8 as Ruby's own file functions do (`rb_str_encode_ospath`, which converts any encoding but UTF-8 and ASCII-8BIT), then to UTF-16, and call the wide functions, keeping the error code across the free:

```diff
-    library->handle = dl_open(libname != Qnil ? StringValueCStr(libname) : NULL, flags);
+#if (defined(_WIN32) || defined(__WIN32__)) && !defined(__CYGWIN__)
+    if (libname != Qnil) libname = rb_str_encode_ospath(libname);
+#endif
+    library->handle = dl_open(libname != Qnil ? StringValueCStr(libname) : NULL, flags);
```

```diff
     } else {
-        DWORD dwFlags = PathIsRelativeA(name) ? 0 : LOAD_WITH_ALTERED_SEARCH_PATH;
-        return LoadLibraryExA(name, NULL, dwFlags);
+        int len = MultiByteToWideChar(CP_UTF8, 0, name, -1, NULL, 0);
+        WCHAR* wname;
+        HMODULE handle;
+        DWORD error;
+        if (len == 0) return NULL;
+        wname = (WCHAR*) xmalloc(len * sizeof(WCHAR));
+        MultiByteToWideChar(CP_UTF8, 0, name, -1, wname, len);
+        handle = LoadLibraryExW(wname, NULL, PathIsRelativeW(wname) ? 0 : LOAD_WITH_ALTERED_SEARCH_PATH);
+        error = GetLastError();
+        xfree(wname);
+        SetLastError(error);
+        return handle;
     }
```

`dl_error` could likewise use `FormatMessageW` and convert the text to UTF-8, so the message is a valid UTF-8 string that Ruby prints.

---

This report was produced entirely by Claude (Anthropic) via Claude Code. [https://declare-ai.org/1.0.0/total.html](https://declare-ai.org/1.0.0/total.html)
