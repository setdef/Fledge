/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * Fledge's launcher for Windows: the program a person runs.
 *
 * A built app is a folder. The launcher sits at its top, renamed to the
 * app's name, beside the app and RubyInstaller's Ruby, whose tree keeps
 * the shape RubyInstaller gives it:
 *
 *   NAME.exe                           this program
 *   app\main.rb                        the app
 *   ruby\bin\x64-ucrt-ruby400.dll      Ruby
 *   ruby\bin\ruby_builtin_dlls\        the DLLs Ruby's DLL needs
 *   ruby\lib\ruby\4.0.0\               Ruby's standard library
 *   ruby\lib\ruby\gems\4.0.0\          Ruby's default gems
 *   notices\                           the licenses of everything above
 *
 * Ruby lives in a DLL, which this program loads when it runs rather than
 * links when it is built. Windows resolves an executable's imports
 * before any of its code runs, searching the executable's own folder,
 * System32, and PATH, never a folder below its own, so a launcher that
 * imported Ruby's DLL would need the DLL beside it, at the top of the
 * app's folder. But Ruby finds its standard library from its DLL's own
 * path: a DLL in PREFIX\bin makes PREFIX the prefix (ruby.c,
 * runtime_libruby_path and ruby_init_loadpath, at Ruby 4.0.9), so the DLL
 * must stay in ruby\bin. LoadLibraryExW by absolute path, and
 * GetProcAddress for the five functions Ruby's own main.c calls, let the
 * launcher sit at the top and Ruby keep its shape. The DLL's own
 * dependencies (libgmp, libwinpthread) load through the private assembly
 * its embedded manifest names, ruby_builtin_dlls, and each extension's
 * (openssl.so needs libssl) through the extension's own
 * *.so-assembly.manifest, so no folder is ever added to PATH. The Windows
 * launcher spike (Plan 001, spike 2) proved this layout, and found the
 * alternatives worse.
 *
 * It starts Ruby the way Ruby's own main.c does (main.c lines 37 to 63
 * at Ruby 4.0.9): setlocale, ruby_sysinit, then, since ruby_start_main
 * is a plain call off WebAssembly (ruby/ruby.h), RUBY_INIT_STACK,
 * ruby_init, and ruby_run_node(ruby_options(...)). Before that it:
 *
 *   1. Keeps every DLL loaded by name to System32 and the folders a DLL
 *      names for itself, never the current folder or PATH, where another
 *      Ruby's DLLs may be (SetDefaultDllDirectories).
 *   2. Finds the folder it lives in (GetModuleFileNameW).
 *   3. Removes every environment variable scrub.c names, from both
 *      copies of the environment Ruby reads (see scrub_environment).
 *      The runtime's own lib\ruby\4.0.0\rubygems\defaults\
 *      operating_system.rb, which replaces RubyInstaller's, then keeps
 *      RubyGems to the runtime's gems, away from the person's own.
 *   4. Runs the app with arguments equivalent to
 *        NAME --disable=rubyopt -I ROOT\app -- ROOT\app\main.rb ARGS
 *      and exits with the app's exit status. RubyInstaller's Ruby has no
 *      YJIT, so unlike on macOS and Linux there is no --yjit.
 *
 * Its entry point is wmain, linked with -municode, as Ruby's own ruby.exe
 * and rubyw.exe are. On Windows, ruby_sysinit discards the argv it is
 * given and rebuilds it from GetCommandLineW as UTF-8 (win32/win32.c,
 * rb_w32_sysinit), so what Ruby sees is the same either way; wmain keeps
 * the C runtime from converting the command line to the ANSI code page
 * on the way, and the paths the launcher adds are UTF-8 from the start.
 *
 * It is built for UCRT, the C runtime RubyInstaller's Ruby uses, so the
 * two share one C runtime: removing a variable from the launcher's copy
 * of the environment removes it from Ruby's. A manifest embedded in the
 * program (windows.manifest, through windows.rc) makes it aware of paths
 * longer than MAX_PATH, as Ruby's own ruby.exe is, and stays with the
 * file when the file is renamed.
 *
 * Built with -DFLEDGE_WINDOWED and linked with -mwindows, it is a
 * GUI-subsystem program, for windowed apps: Windows opens no console for
 * it, and its own failures appear in a message box unless whoever
 * started it captured standard error.
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "launcher.h"

#include <locale.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/*
 * Ruby's headers declare the functions the launcher calls through
 * pointers, so the pointers' types are Ruby's own. Nothing of Ruby is
 * linked, so ruby/subst.h's renames (snprintf to ruby_snprintf and the
 * like) must not apply.
 */
#define RUBY_DONT_SUBST
#include <ruby.h>

/* The DLL's file name, from the RubyInstaller tree the launcher is
 * built against (rake runtime passes it). */
#ifndef FLEDGE_RUBY_DLL
#error "build with -DFLEDGE_RUBY_DLL=L\"x64-ucrt-ruby400.dll\", the name of Ruby's DLL in ruby\\bin"
#endif

/* The launcher's file name, for messages. Set once in wmain. */
static const wchar_t *program_name = L"launcher";

/* Copies the UTF-16 string, or returns NULL when out of memory. */
static char *
utf8_or_null(const wchar_t *wide)
{
    int length = WideCharToMultiByte(CP_UTF8, 0, wide, -1, NULL, 0, NULL, NULL);
    if (length <= 0) return NULL;

    char *narrow = malloc((size_t)length);
    if (narrow == NULL) return NULL;
    if (WideCharToMultiByte(CP_UTF8, 0, wide, -1, narrow, length, NULL, NULL) != length) {
        free(narrow);
        return NULL;
    }
    return narrow;
}

/*
 * Shows a message to whoever ran the app: on standard error when there
 * is one, as UTF-16 to a console and UTF-8 to a file or pipe, and in a
 * message box for a windowed app that has none.
 */
static void
show(const wchar_t *message)
{
    HANDLE error = GetStdHandle(STD_ERROR_HANDLE);
    DWORD mode;
    DWORD written;

    if (error != NULL && error != INVALID_HANDLE_VALUE) {
        if (GetConsoleMode(error, &mode)) {
            WriteConsoleW(error, message, (DWORD)wcslen(message), &written, NULL);
            WriteConsoleW(error, L"\r\n", 2, &written, NULL);
            return;
        }
        char *narrow = utf8_or_null(message);
        if (narrow != NULL) {
            WriteFile(error, narrow, (DWORD)strlen(narrow), &written, NULL);
            WriteFile(error, "\n", 1, &written, NULL);
            free(narrow);
            return;
        }
    }
#ifdef FLEDGE_WINDOWED
    MessageBoxW(NULL, message, program_name, MB_OK | MB_ICONERROR);
#endif
}

/*
 * Shows "NAME: message" and exits with FLEDGE_EXIT_BROKEN_RUNTIME. A
 * person who runs an app never asked for Ruby, so messages name the app,
 * not Ruby.
 */
static void fail(const wchar_t *format, ...) __attribute__((noreturn));

static void
fail(const wchar_t *format, ...)
{
    wchar_t message[4096];
    size_t capacity = sizeof message / sizeof *message;
    va_list arguments;
    int prefix = swprintf(message, capacity, L"%ls: ", program_name);

    if (prefix < 0 || (size_t)prefix >= capacity) prefix = 0;
    va_start(arguments, format);
    vswprintf(message + prefix, capacity - (size_t)prefix, format, arguments);
    va_end(arguments);
    message[capacity - 1] = L'\0';
    show(message);
    exit(FLEDGE_EXIT_BROKEN_RUNTIME);
}

static void *
allocate(size_t count, size_t size)
{
    void *memory = calloc(count, size);
    if (memory == NULL) fail(L"out of memory");
    return memory;
}

static char *
utf8(const wchar_t *wide)
{
    char *narrow = utf8_or_null(wide);
    if (narrow == NULL) fail(L"could not convert %ls to UTF-8", wide);
    return narrow;
}

/* first followed by second, as a new string. */
static wchar_t *
join(const wchar_t *first, const wchar_t *second)
{
    size_t first_length = wcslen(first);
    size_t second_length = wcslen(second);
    wchar_t *joined = allocate(first_length + second_length + 1, sizeof *joined);

    memcpy(joined, first, first_length * sizeof *joined);
    memcpy(joined + first_length, second, (second_length + 1) * sizeof *joined);
    return joined;
}

/*
 * The full path of this program, however long. GetModuleFileNameW
 * truncates silently to the buffer it is given, so the buffer grows
 * until the path fits.
 */
static wchar_t *
own_path(void)
{
    for (DWORD size = MAX_PATH;; size *= 2) {
        wchar_t *buffer = allocate(size, sizeof *buffer);
        DWORD length = GetModuleFileNameW(NULL, buffer, size);

        if (length == 0) fail(L"could not find where this app is (Windows error %lu)", GetLastError());
        if (length < size) return buffer;
        free(buffer);
        if (size >= 65536) fail(L"the path to this app is too long");
    }
}

/*
 * path with the \\?\ prefix that lets Windows' file functions take it
 * past MAX_PATH whatever the registry says, as \\?\UNC\server\share for a
 * network path. path is absolute and normalized, as GetModuleFileNameW
 * returns it, which \\?\ requires.
 */
static wchar_t *
extended_length(const wchar_t *path)
{
    if (wcsncmp(path, L"\\\\?\\", 4) == 0) return join(L"", path);
    if (wcsncmp(path, L"\\\\", 2) == 0) return join(L"\\\\?\\UNC\\", path + 2);
    return join(L"\\\\?\\", path);
}

/*
 * Removes one variable from both copies of the environment Ruby reads:
 * the C runtime's, which Ruby's getenv reads until Ruby has initialized
 * its own (win32/win32.c, w32_getenv), and the process's, which Ruby
 * reads afterwards through GetEnvironmentStringsW and which child
 * processes inherit.
 */
static void
unset(const wchar_t *name)
{
    if (_wputenv_s(name, L"") != 0) fail(L"could not clear %ls from the environment", name);
    if (!SetEnvironmentVariableW(name, NULL) && GetLastError() != ERROR_ENVVAR_NOT_FOUND) {
        fail(L"could not clear %ls from the environment (Windows error %lu)", name, GetLastError());
    }
}

/*
 * Removes every variable scrub.c names, in any case: Windows' variable
 * names ignore case, so bundle_gemfile is BUNDLE_GEMFILE. The names are
 * collected first, because removing a variable invalidates the block
 * being read.
 */
static void
scrub_environment(void)
{
    wchar_t *block = GetEnvironmentStringsW();
    size_t count = 0;

    if (block == NULL) fail(L"could not read the environment (Windows error %lu)", GetLastError());
    for (const wchar_t *entry = block; *entry != L'\0'; entry += wcslen(entry) + 1) count++;

    wchar_t **names = allocate(count + 1, sizeof *names);
    size_t found = 0;
    for (const wchar_t *entry = block; *entry != L'\0'; entry += wcslen(entry) + 1) {
        /* "=C:=C:\folder" entries hold each drive's current folder. */
        if (entry[0] == L'=') continue;

        const wchar_t *equals = wcschr(entry, L'=');
        size_t length = equals != NULL ? (size_t)(equals - entry) : wcslen(entry);
        wchar_t *name = allocate(length + 1, sizeof *name);
        memcpy(name, entry, length * sizeof *name);
        char *narrow = utf8(name);
        if (fledge_is_scrubbed(narrow, 1)) {
            names[found++] = name;
        } else {
            free(name);
        }
        free(narrow);
    }
    FreeEnvironmentStringsW(block);

    for (size_t index = 0; index < found; index++) {
        unset(names[index]);
        free(names[index]);
    }
    free(names);
}

/* The five functions Ruby's main.c calls, typed by Ruby's own headers. */
static struct {
    __typeof__(ruby_sysinit) *sysinit;
    __typeof__(ruby_init_stack) *init_stack;
    __typeof__(ruby_init) *init;
    __typeof__(ruby_options) *options;
    __typeof__(ruby_run_node) *run_node;
} ruby_api;

/*
 * The address of a function Ruby's DLL exports. A FARPROC becomes a
 * typed function pointer through void (*)(void), which C allows between
 * any function pointer types and compilers do not warn about.
 */
typedef void (*any_function)(void);

static any_function
function(HMODULE dll, const char *name, const wchar_t *wide_name)
{
    FARPROC address = GetProcAddress(dll, name);
    if (address == NULL) fail(L"this app is damaged: its Ruby has no %ls", wide_name);
    return (any_function)address;
}

#define RUBY_FUNCTION(name) function(dll, #name, L"" #name)

/*
 * Loads ruby\bin\FLEDGE_RUBY_DLL from the app's folder, letting it find
 * its own dependencies in its own folder and System32 only. Past
 * MAX_PATH, LoadLibraryExW fails with ERROR_FILENAME_EXCED_RANGE even in
 * a process that is aware of long paths (the Windows launcher spike), so
 * it tries again with the \\?\ form of the path.
 */
static void
load_ruby(const wchar_t *folder)
{
    wchar_t *path = join(folder, L"\\ruby\\bin\\" FLEDGE_RUBY_DLL);
    DWORD flags = LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS;
    HMODULE dll = LoadLibraryExW(path, NULL, flags);

    if (dll == NULL && GetLastError() == ERROR_FILENAME_EXCED_RANGE) {
        wchar_t *long_path = extended_length(path);
        dll = LoadLibraryExW(long_path, NULL, flags);
        free(long_path);
    }
    if (dll == NULL) {
        DWORD error = GetLastError();
        if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND || error == ERROR_MOD_NOT_FOUND) {
            fail(L"this app is incomplete: %ls is missing, or a file it needs is (Windows error %lu)", path, error);
        }
        fail(L"could not load %ls (Windows error %lu)", path, error);
    }
    free(path);

    ruby_api.sysinit = (__typeof__(ruby_api.sysinit))RUBY_FUNCTION(ruby_sysinit);
    ruby_api.init_stack = (__typeof__(ruby_api.init_stack))RUBY_FUNCTION(ruby_init_stack);
    ruby_api.init = (__typeof__(ruby_api.init))RUBY_FUNCTION(ruby_init);
    ruby_api.options = (__typeof__(ruby_api.options))RUBY_FUNCTION(ruby_options);
    ruby_api.run_node = (__typeof__(ruby_api.run_node))RUBY_FUNCTION(ruby_run_node);
}

/*
 * As rb_main in Ruby's main.c, with the launcher's arguments: the
 * address of a variable in this frame tells Ruby where the stack it
 * scans for references begins (RUBY_INIT_STACK), so this frame must be
 * a real one, below wmain's.
 */
static int __attribute__((noinline))
run_ruby(int argc, char **argv)
{
    VALUE variable_in_this_stack_frame = 0;

    ruby_api.init_stack(&variable_in_this_stack_frame);
    ruby_api.init();
    return ruby_api.run_node(ruby_api.options(argc, argv));
}

/* Whether path names a file, at any length. */
static int
is_file(const wchar_t *path)
{
    wchar_t *long_path = extended_length(path);
    DWORD attributes = GetFileAttributesW(long_path);

    free(long_path);
    return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

/*
 * What the launcher keeps for the life of the process: the app's folder
 * and the arguments Ruby runs with. Ruby holds on to its arguments, so
 * they are never freed.
 */
static wchar_t *root;
static char **ruby_arguments;

/*
 * Builds the arguments Ruby sees from the ones ruby_sysinit rebuilt from
 * the command line: Ruby's own argv[0], the launcher's options and the
 * app, then everything the person passed.
 */
static int
build_ruby_arguments(int argc, char **argv)
{
    static char disable_rubyopt[] = "--disable=rubyopt";
    static char include[] = "-I";
    static char end_of_options[] = "--";
    static char fallback_name[] = "ruby";
    wchar_t *app = join(root, L"\\app");
    wchar_t *main_rb = join(root, L"\\app\\main.rb");

    if (!is_file(main_rb)) fail(L"this app is incomplete: %ls is missing", main_rb);

    char *before_app_arguments[] = {
        argc > 0 ? argv[0] : fallback_name, disable_rubyopt, include, utf8(app), end_of_options, utf8(main_rb),
    };
    size_t fixed = sizeof before_app_arguments / sizeof before_app_arguments[0];
    size_t count = fixed + (size_t)(argc > 1 ? argc - 1 : 0);

    free(app);
    free(main_rb);
    ruby_arguments = allocate(count + 1, sizeof *ruby_arguments);
    memcpy(ruby_arguments, before_app_arguments, sizeof before_app_arguments);
    for (int index = 1; index < argc; index++) ruby_arguments[fixed + (size_t)index - 1] = argv[index];
    return (int)count;
}

int wmain(int argc, wchar_t **argv);

int
wmain(int argc, wchar_t **argv)
{
    (void)argc;
    (void)argv;

    if (!SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)) {
        fail(L"could not protect this app from other programs' DLLs (Windows error %lu)", GetLastError());
    }

    root = own_path();
    wchar_t *slash = wcsrchr(root, L'\\');
    if (slash == NULL) fail(L"could not find where this app is: %ls", root);
    program_name = slash + 1;
    *slash = L'\0';

    scrub_environment();
    load_ruby(root);

    setlocale(LC_CTYPE, "");
    int ruby_argc = 0;
    char **ruby_argv = NULL;
    ruby_api.sysinit(&ruby_argc, &ruby_argv);
    return run_ruby(build_ruby_arguments(ruby_argc, ruby_argv), ruby_arguments);
}
