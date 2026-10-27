/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 * SPDX-FileComment: Adapted from the Windows launcher spike,
 *   spike/windows/launcher.c on Fledge's spike/windows branch (ebd438d).
 */

/*
 * Fledge's launcher for Windows: the program a person runs.
 *
 * A built app is a folder. The launcher sits at its top, renamed to the
 * app's name, beside the app and RubyInstaller's Ruby, whose tree keeps
 * the shape RubyInstaller gives it:
 *
 *   NAME.exe                           this program
 *   fledge.cfg                         what it runs (config.c)
 *   app\                               the app's project, such as
 *                                      app\main.rb, or
 *                                      app\exe\my_cool_app beside its
 *                                      Gemfile
 *   ruby\bin\x64-ucrt-ruby400.dll      Ruby
 *   ruby\bin\ruby_builtin_dlls\        the DLLs Ruby's DLL needs
 *   ruby\lib\ruby\4.0.0\               Ruby's standard library
 *   ruby\lib\ruby\gems\4.0.0\          Ruby's default and bundled gems,
 *                                      and the app's own
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
 *   2. Finds the folder it lives in (GetModuleFileNameW), and reads
 *      fledge.cfg there, which names the program in app\ to run, ENTRY,
 *      and the app's Gemfile, if it has one.
 *   3. Sets aside every environment variable scrub.c names, removing it
 *      from both copies of the environment Ruby reads (see
 *      scrub_environment). The runtime's own lib\ruby\4.0.0\rubygems\
 *      defaults\operating_system.rb, which replaces RubyInstaller's, then
 *      keeps RubyGems to the runtime's gems, away from the person's own.
 *   4. Runs the app with arguments equivalent to
 *        NAME --disable=rubyopt -- ROOT\app\ENTRY ARGS
 *      which is what ruby ROOT\app\ENTRY ARGS does with no RUBYOPT
 *      (ADR 003): no -I, so the app loads its own files with
 *      require_relative.
 *   5. Once Ruby has booted and before ENTRY runs, fixes RubyGems'
 *      paths, and for an app with a Gemfile has Bundler set up the app's
 *      gems, as bundle exec would (setup_bundler, ADR 005).
 *   6. Then puts the variables of step 3 back, so ENV and the app's
 *      child processes see what they would see without Fledge: as they
 *      were (restore_environment), or for an app with a Gemfile beneath
 *      Bundler's own settings, as bundle exec composes them
 *      (bundle_environment, bundler.c).
 *
 * It exits with the app's exit status, or, when it cannot start the app,
 * with a status from sysexits(3) (launcher.h), as unix.c does.
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
 * Shows "NAME: message" and exits with status, as Ruby's own
 * "ruby: message" does. A person who runs an app never asked for Ruby, so
 * messages name the app, not Ruby (ADR 002).
 */
static void fail_with(int status, const wchar_t *format, ...) __attribute__((noreturn));

static void
fail_with(int status, const wchar_t *format, ...)
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
    exit(status);
}

#define fail(...) fail_with(FLEDGE_EXIT_SOFTWARE, __VA_ARGS__)

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

/* Sets one variable in both copies of the environment, as unset clears
 * it. */
static void
set(const wchar_t *name, const wchar_t *value)
{
    if (_wputenv_s(name, value) != 0) fail(L"could not set %ls in the environment", name);
    if (!SetEnvironmentVariableW(name, value)) {
        fail(L"could not set %ls in the environment (Windows error %lu)", name, GetLastError());
    }
}

/* Whether either copy of the environment holds the variable, in any
 * case. */
static int
is_set(const wchar_t *name)
{
    return _wgetenv(name) != NULL || GetEnvironmentVariableW(name, NULL, 0) != 0;
}

/*
 * The variables scrub_environment set aside, name and value, in the case
 * the person gave them, for restore_environment to put back.
 */
static wchar_t **set_aside_names;
static wchar_t **set_aside_values;
static size_t set_aside_count;

/*
 * Removes every variable scrub.c names, in any case, keeping a copy of
 * each: Windows' variable names ignore case, so bundle_gemfile is
 * BUNDLE_GEMFILE. The variables are collected first, because removing one
 * invalidates the block being read.
 */
static void
scrub_environment(void)
{
    wchar_t *block = GetEnvironmentStringsW();
    size_t count = 0;

    if (block == NULL) fail(L"could not read the environment (Windows error %lu)", GetLastError());
    for (const wchar_t *entry = block; *entry != L'\0'; entry += wcslen(entry) + 1) count++;

    set_aside_names = allocate(count + 1, sizeof *set_aside_names);
    set_aside_values = allocate(count + 1, sizeof *set_aside_values);
    for (const wchar_t *entry = block; *entry != L'\0'; entry += wcslen(entry) + 1) {
        /* "=C:=C:\folder" entries hold each drive's current folder. */
        if (entry[0] == L'=') continue;

        const wchar_t *equals = wcschr(entry, L'=');
        size_t length = equals != NULL ? (size_t)(equals - entry) : wcslen(entry);
        wchar_t *name = allocate(length + 1, sizeof *name);
        memcpy(name, entry, length * sizeof *name);
        char *narrow = utf8(name);
        if (fledge_is_scrubbed(narrow, 1)) {
            set_aside_names[set_aside_count] = name;
            set_aside_values[set_aside_count] = join(L"", equals != NULL ? equals + 1 : L"");
            set_aside_count++;
        } else {
            free(name);
        }
        free(narrow);
    }
    FreeEnvironmentStringsW(block);

    for (size_t index = 0; index < set_aside_count; index++) unset(set_aside_names[index]);
}

/* Forgets the variables scrub_environment set aside, once they are back. */
static void
forget_set_aside(void)
{
    for (size_t index = 0; index < set_aside_count; index++) {
        free(set_aside_names[index]);
        free(set_aside_values[index]);
    }
    free(set_aside_names);
    free(set_aside_values);
    set_aside_names = NULL;
    set_aside_values = NULL;
    set_aside_count = 0;
}

/*
 * Puts back every variable scrub_environment set aside, with its original
 * value, in both copies of the environment, for an app without a
 * Gemfile, whose boot sets none of them. Once Ruby has initialized, its
 * ENV reads the process's copy
 * on every access (win32/win32.c, w32_getenv, through
 * GetEnvironmentStringsW), so the app's ENV, and every process it starts,
 * see them. Ruby's own gem_prelude.rb does the same with BUNDLER_SETUP: it
 * removes the variable while RubyGems loads and puts it back afterwards.
 */
static void
restore_environment(void)
{
    for (size_t index = 0; index < set_aside_count; index++) {
        const wchar_t *name = set_aside_names[index];

        if (!is_set(name)) set(name, set_aside_values[index]);
    }
    forget_set_aside();
}

/*
 * The five functions Ruby's main.c calls, and the two the launcher calls
 * between ruby_options and ruby_run_node, typed by Ruby's own headers.
 */
static struct {
    __typeof__(ruby_sysinit) *sysinit;
    __typeof__(ruby_init_stack) *init_stack;
    __typeof__(ruby_init) *init;
    __typeof__(ruby_options) *options;
    __typeof__(ruby_executable_node) *executable_node;
    __typeof__(rb_eval_string_protect) *eval_string_protect;
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
    ruby_api.executable_node = (__typeof__(ruby_api.executable_node))RUBY_FUNCTION(ruby_executable_node);
    ruby_api.eval_string_protect = (__typeof__(ruby_api.eval_string_protect))RUBY_FUNCTION(rb_eval_string_protect);
    ruby_api.run_node = (__typeof__(ruby_api.run_node))RUBY_FUNCTION(ruby_run_node);
}

/*
 * Has RubyGems work out its gem paths now, from the environment Ruby
 * booted with, before restore_environment puts GEM_HOME and GEM_PATH
 * back. Gem.paths reads them once and keeps the answer (rubygems.rb,
 * Gem.paths, at Ruby 4.0.9), so the app's gems stay the runtime's even
 * when the person has GEM_HOME set; a child Ruby the app starts still
 * reads the person's own.
 */
static void
pin_rubygems(void)
{
    int state = 0;

    ruby_api.eval_string_protect("Gem.paths if defined?(Gem.paths)", &state);
    if (state != 0) fail(L"could not start RubyGems");
}

/*
 * What the launcher keeps for the life of the process: the app's folder,
 * what its fledge.cfg says, with ENTRY and the Gemfile as Windows paths,
 * and the arguments Ruby runs with. Ruby holds on to its arguments, so
 * they are never freed.
 */
static wchar_t *root;
static struct fledge_config app_config;
static wchar_t *entry;
static wchar_t *gemfile;
static char **ruby_arguments;

/* The UTF-8 path from fledge.cfg as a wide Windows path, with \ for /. */
static wchar_t *
windows_path(const char *path)
{
    int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    if (length <= 0) fail(L"this app is damaged: its %hs names a path that is not UTF-8", FLEDGE_CONFIG);

    wchar_t *wide = allocate((size_t)length, sizeof *wide);
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, length);
    for (wchar_t *letter = wide; *letter != L'\0'; letter++) {
        if (*letter == L'/') *letter = L'\\';
    }
    return wide;
}

/*
 * Reads ROOT\fledge.cfg into app_config (config.c). A missing file is a
 * missing input, as a missing ENTRY is (EX_NOINPUT); one that cannot be
 * read or says something wrong is a damaged app.
 */
static void
read_config(void)
{
    static char text[65536];
    wchar_t *path = join(root, L"\\" FLEDGE_CONFIG);
    wchar_t *long_path = extended_length(path);
    DWORD attributes = GetFileAttributesW(long_path);
    const char *problem = "is unreadable";

    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
        fail_with(FLEDGE_EXIT_NO_APP, L"this app is incomplete: %ls is missing", path);
    }
    FILE *file = _wfopen(long_path, L"rb");
    free(long_path);
    if (file == NULL) fail(L"could not read %ls", path);
    size_t size = fread(text, 1, sizeof text - 1, file);
    int unreadable = ferror(file);
    fclose(file);
    if (unreadable) fail(L"could not read %ls", path);
    if (size == sizeof text - 1 || memchr(text, '\0', size) != NULL) {
        fail(L"this app is damaged: %ls is not a fledge.cfg", path);
    }
    text[size] = '\0';
    if (fledge_parse_config(text, &app_config, &problem) != 0) fail(L"this app is damaged: %ls %hs", path, problem);
    free(path);

    entry = windows_path(app_config.entry);
    if (app_config.gemfile != NULL) gemfile = windows_path(app_config.gemfile);
}

/*
 * The Ruby that loads Bundler, and that has Bundler set up the app's
 * gems, by their paths in Ruby's own library, as bundle exec's
 * RUBYOPT=-r.../bundler/setup does (bundler/shared_helpers.rb,
 * set_rubyopt): required by name, RubyGems would activate the bundler gem
 * first, loading what bundle exec does not. The second prints what went
 * wrong when it cannot. bundler/setup prints its
 * own message and exits when standard output is a console; otherwise it
 * raises, quietly.
 */
static const char require_bundler[] = "require File.join(RbConfig::CONFIG['rubylibdir'], 'bundler')";
static const char bundler_setup[] = "begin\n"
                                    "  require File.join(RbConfig::CONFIG['rubylibdir'], 'bundler/setup')\n"
                                    "rescue StandardError => e\n"
                                    "  $stderr.puts(e.message)\n"
                                    "  raise\n"
                                    "end\n";

/*
 * Has Bundler set up the gems of the app's Gemfile, which fledge build
 * installed into the runtime's gem folder, as bundle exec would before
 * running ENTRY (ADR 005), as unix.c does. BUNDLE_GEMFILE names the app's
 * Gemfile, and BUNDLE_USER_CONFIG names the app's own .bundle\config,
 * which fledge build wrote, in place of %USERPROFILE%\.bundle\config, so
 * nothing of the person's changes which gems load. Bundler is required
 * first, so the environment it records as the one it started from is the
 * one Ruby booted with, which bundle_environment then completes with the
 * person's own.
 */
static void
setup_bundler(void)
{
    int state = 0;
    wchar_t *app = join(root, L"\\app\\");
    wchar_t *gemfile_path = join(app, gemfile);
    wchar_t *settings = join(app, L".bundle\\config");

    ruby_api.eval_string_protect(require_bundler, &state);
    if (state != 0) fail(L"could not start Bundler");
    set(L"BUNDLE_GEMFILE", gemfile_path);
    set(L"BUNDLE_USER_CONFIG", settings);
    ruby_api.eval_string_protect(bundler_setup, &state);
    if (state != 0) fail(L"could not set up this app's gems");
    unset(L"BUNDLE_USER_CONFIG");
    free(app);
    free(gemfile_path);
    free(settings);
}

/*
 * Puts back every variable scrub_environment set aside for an app with a
 * Gemfile, once Bundler has set up its gems, beneath Bundler's own
 * settings, as bundle exec would have composed them, as unix.c does
 * (bundler.c; ADR 005, section 5). Ruby's ENV on Windows is UTF-8
 * (hash.c, env_encoding), so the variables go to Ruby as UTF-8, in the
 * case the person gave their names.
 */
static void
bundle_environment(void)
{
    size_t length = 0;
    char **entries = allocate(set_aside_count + 1, sizeof *entries);

    for (size_t index = 0; index < set_aside_count; index++) {
        char *name = utf8(set_aside_names[index]);
        char *value = utf8(set_aside_values[index]);
        size_t name_length = strlen(name);
        size_t value_length = strlen(value);

        entries[index] = allocate(name_length + value_length + 2, 1);
        memcpy(entries[index], name, name_length);
        entries[index][name_length] = '=';
        memcpy(entries[index] + name_length + 1, value, value_length + 1);
        length += name_length + value_length + 2;
        free(name);
        free(value);
    }

    char *variables = allocate(length + 1, 1);
    char *next = variables;
    for (size_t index = 0; index < set_aside_count; index++) {
        size_t size = strlen(entries[index]) + 1;
        memcpy(next, entries[index], size);
        next += size;
        free(entries[index]);
    }
    free(entries);

    char *code = fledge_bundle_environment_code(variables, length);
    free(variables);
    if (code == NULL) fail(L"out of memory");

    int state = 0;
    ruby_api.eval_string_protect(code, &state);
    free(code);
    if (state != 0) fail(L"could not set up this app's environment");
    forget_set_aside();
}

/*
 * As rb_main in Ruby's main.c, with the launcher's arguments: the
 * address of a variable in this frame tells Ruby where the stack it
 * scans for references begins (RUBY_INIT_STACK), so this frame must be
 * a real one, below wmain's.
 *
 * SPDX-SnippetBegin
 * SPDX-License-Identifier: Ruby OR BSD-2-Clause
 * SPDX-SnippetCopyrightText: 1993-2007 Yukihiro Matsumoto
 * SPDX-SnippetComment: rb_main, adapted from Ruby's main.c (lines 37 to
 *   43) at Ruby v4.0.9 (3e93b23afc), with RUBY_INIT_STACK spelled out
 *   through a function pointer, and pin_rubygems, setup_bundler,
 *   bundle_environment, and restore_environment between ruby_options and
 *   ruby_run_node.
 */
static int __attribute__((noinline))
run_ruby(int argc, char **argv)
{
    VALUE variable_in_this_stack_frame = 0;

    ruby_api.init_stack(&variable_in_this_stack_frame);
    ruby_api.init();
    void *node = ruby_api.options(argc, argv);
    if (ruby_api.executable_node(node, NULL)) {
        pin_rubygems();
        if (gemfile != NULL) {
            setup_bundler();
            pin_rubygems();
            bundle_environment();
        }
    }
    restore_environment();
    return ruby_api.run_node(node);
}
/* SPDX-SnippetEnd */

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
 * Builds the arguments Ruby sees from the ones ruby_sysinit rebuilt from
 * the command line: Ruby's own argv[0], the launcher's options and the
 * app, then everything the person passed.
 */
static int
build_ruby_arguments(int argc, char **argv)
{
    static char disable_rubyopt[] = "--disable=rubyopt";
    static char end_of_options[] = "--";
    static char fallback_name[] = "ruby";
    wchar_t *app = join(root, L"\\app\\");
    wchar_t *program = join(app, entry);

    free(app);
    if (!is_file(program)) fail_with(FLEDGE_EXIT_NO_APP, L"this app is incomplete: %ls is missing", program);

    char *before_app_arguments[] = {
        argc > 0 ? argv[0] : fallback_name,
        disable_rubyopt,
        end_of_options,
        utf8(program),
    };
    size_t fixed = sizeof before_app_arguments / sizeof before_app_arguments[0];
    size_t count = fixed + (size_t)(argc > 1 ? argc - 1 : 0);

    free(program);
    ruby_arguments = allocate(count + 1, sizeof *ruby_arguments);
    memcpy(ruby_arguments, before_app_arguments, sizeof before_app_arguments);
    for (int index = 1; index < argc; index++) ruby_arguments[fixed + (size_t)index - 1] = argv[index];
    return (int)count;
}

int wmain(int argc, wchar_t **argv);

/*
 * SPDX-SnippetBegin
 * SPDX-License-Identifier: Ruby OR BSD-2-Clause
 * SPDX-SnippetCopyrightText: 1993-2007 Yukihiro Matsumoto
 * SPDX-SnippetComment: wmain and main, adapted from Ruby's main.c (lines
 *   45 to 63) at Ruby v4.0.9 (3e93b23afc), which on Windows hands
 *   ruby_sysinit no arguments for it to rebuild from the command line,
 *   with the launcher's own steps before ruby_sysinit.
 */
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

    read_config();
    scrub_environment();
    load_ruby(root);

    setlocale(LC_CTYPE, "");
    int ruby_argc = 0;
    char **ruby_argv = NULL;
    ruby_api.sysinit(&ruby_argc, &ruby_argv);
    int count = build_ruby_arguments(ruby_argc, ruby_argv);
    return run_ruby(count, ruby_arguments);
}
/* SPDX-SnippetEnd */
