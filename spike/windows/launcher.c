/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * SPIKE: Fledge's Windows launcher, as a reference for the real one.
 *
 * A Fledge app on Windows is a folder:
 *
 *     hello\
 *       hello.exe                     <- this program, renamed per app
 *       app\main.rb                   <- the app
 *       ruby\bin\x64-ucrt-ruby400.dll <- RubyInstaller's tree, unchanged
 *       ruby\bin\ruby_builtin_dlls\   <- found by the DLL's own manifest
 *       ruby\lib\ruby\...             <- found relative to the DLL
 *
 * It embeds CRuby as Ruby's own main.c (v4.0.9) does: setlocale,
 * ruby_sysinit, then (ruby_start_main is a plain call off wasm)
 * RUBY_INIT_STACK, ruby_init, ruby_options, ruby_run_node.
 *
 * Why the DLL is loaded at run time instead of imported: Windows
 * resolves an executable's imports before main runs, searching the
 * executable's own folder, System32 and PATH, never a subfolder. CRuby
 * finds its prefix from the DLL's own path (ruby.c, runtime_libruby_path
 * and ruby_init_loadpath: a DLL in .../bin gives the prefix ...), so the
 * DLL must stay in ruby\bin, out of the import search. LoadLibraryExW
 * with an absolute path, then GetProcAddress for the five functions
 * main.c calls, lets hello.exe sit at the top of the folder. The DLL's
 * own dependencies (libgmp, libwinpthread) resolve through the
 * ruby_builtin_dlls private assembly its embedded manifest names, and
 * each extension's (openssl.so -> libssl) through its own
 * *.so-assembly.manifest, so no PATH change is ever needed.
 *
 * Build modes (spike only):
 *   default             load ruby\bin\<FLEDGE_RUBY_DLL> at run time
 *   -DFLEDGE_IMPORT     link the import library instead (for Q1); the
 *                       exe must then sit beside the DLL, in ruby\bin
 *   -DFLEDGE_WINDOWED   GUI subsystem (link with -mwindows): errors go
 *                       to a message box, since there is no console
 *   -DFLEDGE_DISABLE_GEMS  pass --disable-gems (proves DLL loading does
 *                       not depend on RubyInstaller's rubygems hook)
 *
 * Compile (MSYS2 UCRT64 gcc):
 *   gcc -std=gnu11 -O2 -Wall -Wextra -Werror -municode \
 *       -isystem <ri>/include/ruby-4.0.0 -isystem <ri>/include/ruby-4.0.0/x64-mingw-ucrt \
 *       launcher.c launcher.res.o -o launcher.exe -static-libgcc
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/*
 * ruby.h only for the API's declarations; in the default mode nothing
 * from it is linked, but __typeof__ checks our function pointers against
 * the real prototypes.
 */
/* No ruby/subst.h renames (snprintf -> ruby_snprintf): this file calls
 * no Ruby function by name outside the import-library mode. */
#define RUBY_DONT_SUBST
#include <ruby.h>

#ifndef FLEDGE_RUBY_DLL
#define FLEDGE_RUBY_DLL L"x64-ucrt-ruby400.dll"
#endif

/* EX_SOFTWARE from sysexits.h: the launcher itself failed. */
#define FLEDGE_EXIT_LAUNCHER 70

/*
 * Ruby environment variables a person's machine may set that would
 * change the app (ADR 001, section 1), plus the two RubyInstaller's
 * runtime reads (RUBY_DLL_PATH adds DLL directories;
 * RI_FORCE_PATH_FOR_DLL makes it prepend them to PATH). Every BUNDLE_
 * variable is scrubbed too, by prefix.
 */
static const wchar_t *const scrubbed[] = {
    L"RUBYLIB", L"RUBYOPT", L"RUBYSHELL", L"RUBYPATH",
    L"GEM_HOME", L"GEM_PATH", L"GEM_SPEC_CACHE",
    L"RUBY_DLL_PATH", L"RI_FORCE_PATH_FOR_DLL",
};

static void fail(const wchar_t *what, const wchar_t *detail)
{
    wchar_t message[1024];
    _snwprintf(message, sizeof message / sizeof *message - 1,
               L"This app could not start.\n\n%ls\n%ls", what,
               detail ? detail : L"");
    message[sizeof message / sizeof *message - 1] = L'\0';
#ifdef FLEDGE_WINDOWED
    MessageBoxW(NULL, message, L"Error", MB_OK | MB_ICONERROR);
#else
    fwprintf(stderr, L"%ls\n", message);
#endif
    exit(FLEDGE_EXIT_LAUNCHER);
}

/* The full path of this executable, however long (\\?\ paths included). */
static wchar_t *own_path(void)
{
    DWORD size = MAX_PATH;
    for (;;) {
        wchar_t *buffer = malloc(size * sizeof *buffer);
        if (!buffer) fail(L"Out of memory.", NULL);
        DWORD length = GetModuleFileNameW(NULL, buffer, size);
        if (length == 0) fail(L"GetModuleFileNameW failed.", NULL);
        if (length < size) return buffer;
        free(buffer);
        size *= 2;
    }
}

/* dir + suffix, as a new wide string. */
static wchar_t *join(const wchar_t *dir, const wchar_t *suffix)
{
    size_t length = wcslen(dir) + wcslen(suffix) + 1;
    wchar_t *joined = malloc(length * sizeof *joined);
    if (!joined) fail(L"Out of memory.", NULL);
    wcscpy(joined, dir);
    wcscat(joined, suffix);
    return joined;
}

/* Ruby on Windows takes paths in argv as UTF-8 (win32.c, rb_w32_sysinit). */
static char *utf8(const wchar_t *wide)
{
    int length = WideCharToMultiByte(CP_UTF8, 0, wide, -1, NULL, 0, NULL, NULL);
    char *narrow = malloc(length ? length : 1);
    if (!narrow || !length) fail(L"Could not convert a path to UTF-8.", wide);
    WideCharToMultiByte(CP_UTF8, 0, wide, -1, narrow, length, NULL, NULL);
    return narrow;
}

/*
 * Removes a variable from both copies of the environment: the C
 * runtime's (which Ruby's getenv falls back to before init_env runs,
 * win32.c w32_getenv) and the process's (which Ruby reads afterwards,
 * through GetEnvironmentStringsW, and which child processes inherit).
 */
static void unset(const wchar_t *name)
{
    _wputenv_s(name, L"");
    SetEnvironmentVariableW(name, NULL);
}

static void scrub_environment(void)
{
    for (size_t i = 0; i < sizeof scrubbed / sizeof *scrubbed; i++)
        unset(scrubbed[i]);

    /* Collect BUNDLE_* names first: unsetting while walking the block
     * would invalidate it. Names are case-insensitive on Windows. */
    wchar_t *block = GetEnvironmentStringsW();
    if (!block) return;
    size_t count = 0;
    for (wchar_t *entry = block; *entry; entry += wcslen(entry) + 1)
        if (_wcsnicmp(entry, L"BUNDLE_", 7) == 0) count++;
    wchar_t **names = calloc(count + 1, sizeof *names);
    size_t found = 0;
    for (wchar_t *entry = block; names && *entry; entry += wcslen(entry) + 1) {
        if (_wcsnicmp(entry, L"BUNDLE_", 7) != 0) continue;
        const wchar_t *equals = wcschr(entry, L'=');
        size_t length = equals ? (size_t)(equals - entry) : wcslen(entry);
        names[found] = calloc(length + 1, sizeof **names);
        if (names[found]) wcsncpy(names[found++], entry, length);
    }
    FreeEnvironmentStringsW(block);
    for (size_t i = 0; i < found; i++) {
        unset(names[i]);
        free(names[i]);
    }
    free(names);
}

/* The five entry points main.c uses, typed by Ruby's own headers. */
static struct {
    __typeof__(ruby_sysinit) *sysinit;
    __typeof__(ruby_init_stack) *init_stack;
    __typeof__(ruby_init) *init;
    __typeof__(ruby_options) *options;
    __typeof__(ruby_run_node) *run_node;
} ruby;

#ifdef FLEDGE_IMPORT
static void load_ruby(const wchar_t *base)
{
    (void)base;
    ruby.sysinit = ruby_sysinit;
    ruby.init_stack = ruby_init_stack;
    ruby.init = ruby_init;
    ruby.options = ruby_options;
    ruby.run_node = ruby_run_node;
}
#else
static FARPROC symbol(HMODULE dll, const char *name)
{
    FARPROC address = GetProcAddress(dll, name);
    if (!address) {
        wchar_t wide[64];
        MultiByteToWideChar(CP_UTF8, 0, name, -1, wide, 64);
        fail(L"Ruby's DLL lacks a function:", wide);
    }
    return address;
}

static void load_ruby(const wchar_t *base)
{
    wchar_t *path = join(base, L"ruby\\bin\\" FLEDGE_RUBY_DLL);
    /* Search only the DLL's own folder and System32 for its imports:
     * never the current directory or PATH, where another Ruby's DLLs
     * may be. (Its private assembly is found by its manifest either way.) */
    HMODULE dll = LoadLibraryExW(path, NULL,
                                 LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR |
                                 LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    if (!dll) {
        wchar_t detail[64];
        _snwprintf(detail, 63, L"(error %lu)", GetLastError());
        detail[63] = L'\0';
        fail(path, detail);
    }
    free(path);
    /* Function pointer casts through FARPROC are how GetProcAddress is
     * meant to be used; -Wcast-function-type is silenced per cast. */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wcast-function-type"
    ruby.sysinit = (__typeof__(ruby.sysinit))symbol(dll, "ruby_sysinit");
    ruby.init_stack = (__typeof__(ruby.init_stack))symbol(dll, "ruby_init_stack");
    ruby.init = (__typeof__(ruby.init))symbol(dll, "ruby_init");
    ruby.options = (__typeof__(ruby.options))symbol(dll, "ruby_options");
    ruby.run_node = (__typeof__(ruby.run_node))symbol(dll, "ruby_run_node");
#pragma GCC diagnostic pop
}
#endif

/* main.c's rb_main: RUBY_INIT_STACK marks this frame as the stack's base. */
static int __attribute__((noinline)) run(int argc, char **argv)
{
    VALUE variable_in_this_stack_frame;
    ruby.init_stack(&variable_in_this_stack_frame);
    ruby.init();
    return ruby.run_node(ruby.options(argc, argv));
}

/*
 * wmain, linked with -municode, as Ruby's own ruby.exe and rubyw.exe are
 * (main.c, cygwin/GNUmakefile.in). The arguments are unused on purpose:
 * ruby_sysinit on Windows discards argc/argv and rebuilds them from
 * GetCommandLineW as UTF-8 (win32.c, rb_w32_sysinit), so main or wmain
 * makes no difference to what Ruby sees; wmain keeps the C runtime from
 * converting the command line to the ANSI code page first.
 */
int wmain(int unused_argc, wchar_t **unused_argv)
{
    (void)unused_argc;
    (void)unused_argv;

    /* Keep a hostile PATH or current directory from supplying any DLL
     * this process loads by name later (what RubyInstaller's
     * operating_system.rb also does, through RubyInstaller::Runtime). */
    SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);

    wchar_t *self = own_path();
    wchar_t *slash = wcsrchr(self, L'\\');
    if (!slash) fail(L"Could not find this app's folder.", self);
    slash[1] = L'\0'; /* self is now the folder, with its trailing \ */

#ifdef FLEDGE_IMPORT
    /* The import-linked spike build lives in ruby\bin, beside the DLL. */
    wchar_t *top = join(self, L"..\\..\\");
    free(self);
    self = top;
#endif

    scrub_environment();
    load_ruby(self);

    wchar_t *main_rb = join(self, L"app\\main.rb");
    if (GetFileAttributesW(main_rb) == INVALID_FILE_ATTRIBUTES)
        fail(L"Missing:", main_rb);
    wchar_t *app_dir = join(self, L"app");
    wchar_t *include = join(L"-I", app_dir);

    setlocale(LC_CTYPE, "");

    int argc = 0;
    char **argv = NULL;
    ruby.sysinit(&argc, &argv);

    /* ruby [-I app] [--disable-gems] -- app\main.rb ARGS... */
    char **ruby_argv = calloc((size_t)argc + 6, sizeof *ruby_argv);
    if (!ruby_argv) fail(L"Out of memory.", NULL);
    int n = 0;
    ruby_argv[n++] = argc > 0 ? argv[0] : "ruby";
    ruby_argv[n++] = utf8(include);
#ifdef FLEDGE_DISABLE_GEMS
    ruby_argv[n++] = "--disable-gems";
#endif
    ruby_argv[n++] = "--";
    ruby_argv[n++] = utf8(main_rb);
    for (int i = 1; i < argc; i++) ruby_argv[n++] = argv[i];
    ruby_argv[n] = NULL;

    return run(n, ruby_argv);
}
