/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * What a Windows runtime's ruby.exe and rubyw.exe add to Ruby's main.c
 * (ruby_main.c): the DLLs the app's Ruby may load, and handing an app's
 * own program back to the app's launcher (ADR 026;
 * doc/contributors/design/launcher.md, "bin/ruby and restarts"), as
 * relaunch.c does for bin/ruby on macOS and Linux.
 *
 * A Ruby program restarts itself with exec RbConfig.ruby, $0, *ARGV. In a
 * built app RbConfig.ruby is ROOT\ruby\bin\ruby.exe, and $0 is the
 * program fledge.cfg names, ROOT\app\ENTRY. Ruby's own main.c would run
 * it as plain Ruby, with the person's RUBYOPT, RUBYLIB, and GEM_HOME,
 * which the launcher put back before the app ran, without Bundler set up
 * as the launcher sets it up, and under the system's ANSI code page,
 * where the launcher's manifest declares UTF-8 (ADR 070). So, once
 * ruby_sysinit has read the command line as Ruby reads it, ruby.exe asks
 * what bin/ruby asks: is its first argument the program a launcher of
 * this app runs? If so, it runs that launcher with the rest of its own
 * command line, exactly as it was given, waits for it, and exits with its
 * status. Windows has no exec that keeps the process, and Ruby's own exec
 * there does the same: it starts the program, waits, and exits with the
 * program's status (process.c, line 1639, and win32/win32.c's
 * child_result, lines 1188 to 1203, at Ruby 0e25874222). The launcher
 * then hides the person's Ruby settings, sets up the app's gems, sets its
 * AppUserModelID, and puts the settings back, as it did the first time.
 *
 * A launcher of this app is a file in ROOT, three folders above this
 * program, whose name ends in .exe, that is no link, that holds
 * FLEDGE_LAUNCHER_MARK (windows.c), and whose section of ROOT\fledge.cfg,
 * the one with its own name less .exe (ADR 024), or the whole file when
 * it has no sections, names an entry that is the script. The mark keeps
 * an installer's uninstall.exe, which sits beside the launcher
 * (Fledge::NSIS::UNINSTALLER), from passing for it in an app of one
 * program. Files are compared as Windows sees them, by volume serial
 * number and file index (GetFileInformationByHandle), as relaunch.c
 * compares device and inode, so a relative path, a short name, or a
 * different case all name the same entry.
 *
 * Anything else stays Ruby's: a first argument that is an option, a
 * script that is not an entry, a runtime with no fledge.cfg, and a
 * command line this cannot split exactly as Ruby does. Ruby splits its
 * command line by its own rules (win32/win32.c, w32_cmdvector), which add
 * single quotes and file name patterns to Microsoft's rules for double
 * quotes ("Parsing C++ command-line arguments"). The arguments after the
 * script are passed on as written, for the launcher's Ruby to split as
 * this one would have; the program's own name and the script, which are
 * not, must each be written as Ruby's own exec writes them (win32/win32.c,
 * join_argv): either plain, with no quote, or in double quotes with no
 * quote inside, and the script with no character of a file name
 * pattern, which Ruby would expand. A launcher found but not started is
 * a damaged app: ruby.exe says so and exits with EX_SOFTWARE, as the
 * launcher would, rather than run the app as plain Ruby.
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "launcher.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/* fledge.cfg is at most this long, as windows.c reads it. */
#define CONFIG_SIZE 65536

/* The UTF-8 string as a new UTF-16 one, or NULL. */
static wchar_t *
wide(const char *text)
{
    int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
    if (length <= 0) return NULL;

    wchar_t *result = calloc((size_t)length, sizeof *result);
    if (result != NULL && MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, result, length) != length) {
        free(result);
        return NULL;
    }
    return result;
}

/* The UTF-16 string as a new UTF-8 one, or NULL. */
static char *
narrow(const wchar_t *text)
{
    int length = WideCharToMultiByte(CP_UTF8, 0, text, -1, NULL, 0, NULL, NULL);
    if (length <= 0) return NULL;

    char *result = malloc((size_t)length);
    if (result != NULL && WideCharToMultiByte(CP_UTF8, 0, text, -1, result, length, NULL, NULL) != length) {
        free(result);
        return NULL;
    }
    return result;
}

/* first, second, and third, joined as a new string, or NULL. */
static wchar_t *
join(const wchar_t *first, const wchar_t *second, const wchar_t *third)
{
    size_t lengths[] = {wcslen(first), wcslen(second), wcslen(third)};
    wchar_t *joined = calloc(lengths[0] + lengths[1] + lengths[2] + 1, sizeof *joined);

    if (joined == NULL) return NULL;
    memcpy(joined, first, lengths[0] * sizeof *joined);
    memcpy(joined + lengths[0], second, lengths[1] * sizeof *joined);
    memcpy(joined + lengths[0] + lengths[1], third, (lengths[2] + 1) * sizeof *joined);
    return joined;
}

/* This program's full path, however long, or NULL. */
static wchar_t *
own_path(void)
{
    for (DWORD size = MAX_PATH; size <= 65536; size *= 2) {
        wchar_t *buffer = calloc(size, sizeof *buffer);
        if (buffer == NULL) return NULL;

        DWORD length = GetModuleFileNameW(NULL, buffer, size);
        if (length > 0 && length < size) return buffer;
        free(buffer);
        if (length == 0) return NULL;
    }
    return NULL;
}

/*
 * path, made absolute, with the \\?\ prefix that lets Windows' file
 * functions take it past MAX_PATH (\\?\UNC\ for a network path), as
 * windows.c opens the app's files, or NULL.
 */
static wchar_t *
long_form(const wchar_t *path)
{
    DWORD size = GetFullPathNameW(path, 0, NULL, NULL);
    wchar_t *full = size == 0 ? NULL : calloc(size, sizeof *full);

    if (full == NULL) return NULL;
    DWORD length = GetFullPathNameW(path, size, full, NULL);
    if (length == 0 || length >= size) {
        free(full);
        return NULL;
    }

    wchar_t *result;
    if (wcsncmp(full, L"\\\\?\\", 4) == 0) {
        result = join(full, L"", L"");
    } else if (wcsncmp(full, L"\\\\", 2) == 0) {
        result = join(L"\\\\?\\UNC\\", full + 2, L"");
    } else {
        result = join(L"\\\\?\\", full, L"");
    }
    free(full);
    return result;
}

/* What identifies a file to Windows, whatever the path that names it. */
struct identity {
    DWORD volume;
    DWORD index_high;
    DWORD index_low;
};

/* Writes the identity of the regular file at path, not a link, into
 * file. Returns 1, or 0 when path names no such file. */
static int
identify(const wchar_t *path, struct identity *file)
{
    wchar_t *long_path = long_form(path);
    if (long_path == NULL) return 0;

    HANDLE handle = CreateFileW(long_path, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                NULL, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    free(long_path);
    if (handle == INVALID_HANDLE_VALUE) return 0;

    BY_HANDLE_FILE_INFORMATION information;
    int found = GetFileInformationByHandle(handle, &information) &&
                (information.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) == 0;
    CloseHandle(handle);
    if (found) {
        file->volume = information.dwVolumeSerialNumber;
        file->index_high = information.nFileIndexHigh;
        file->index_low = information.nFileIndexLow;
    }
    return found;
}

static int
same_file(const struct identity *one, const struct identity *other)
{
    return one->volume == other->volume && one->index_high == other->index_high && one->index_low == other->index_low;
}

/* Reads the file at path into text, of CONFIG_SIZE bytes, as one
 * NUL-terminated string. Returns 0, or -1. */
static int
read_config(const wchar_t *path, char *text)
{
    wchar_t *long_path = long_form(path);
    FILE *file = long_path == NULL ? NULL : _wfopen(long_path, L"rb");

    free(long_path);
    if (file == NULL) return -1;
    size_t length = fread(text, 1, CONFIG_SIZE - 1, file);
    int failed = ferror(file);
    fclose(file);
    if (failed || length == CONFIG_SIZE - 1 || memchr(text, '\0', length) != NULL) return -1;
    text[length] = '\0';
    return 0;
}

/* Whether two UTF-8 program names are the same to Windows, ignoring
 * case as NTFS does, as windows.c compares them. */
static int
same_program_name(const char *one, const char *other)
{
    wchar_t *wide_one = wide(one);
    wchar_t *wide_other = wide(other);
    int same = wide_one != NULL && wide_other != NULL &&
               CompareStringOrdinal(wide_one, -1, wide_other, -1, TRUE) == CSTR_EQUAL;

    free(wide_one);
    free(wide_other);
    return same;
}

/* Whether the file at path holds FLEDGE_LAUNCHER_MARK, read in pieces
 * that overlap by the mark's length, so the mark is found across two. */
static int
holds_mark(const wchar_t *path)
{
    static const char mark[] = FLEDGE_LAUNCHER_MARK;
    enum { MARK = sizeof mark - 1, PIECE = 65536 };
    static char buffer[MARK + PIECE];
    wchar_t *long_path = long_form(path);
    FILE *file = long_path == NULL ? NULL : _wfopen(long_path, L"rb");
    size_t kept = 0;
    int found = 0;

    free(long_path);
    if (file == NULL) return 0;
    for (size_t count; !found && (count = fread(buffer + kept, 1, PIECE, file)) > 0;) {
        size_t length = kept + count;
        for (size_t at = 0; !found && at + MARK <= length; at++) {
            found = buffer[at] == mark[0] && memcmp(buffer + at, mark, MARK) == 0;
        }
        kept = length < MARK ? length : MARK;
        memmove(buffer, buffer + length - kept, kept);
    }
    fclose(file);
    return found;
}

/*
 * Whether the program named name, in the folder root, runs script: its
 * part of the fledge.cfg text config names an entry in root\app that is
 * script.
 */
static int
runs_script(const wchar_t *root, const wchar_t *name, const char *config, const struct identity *script)
{
    static char text[CONFIG_SIZE];
    struct fledge_config program;
    const char *problem = NULL;
    struct identity entry;
    wchar_t *stem = join(name, L"", L"");
    size_t length = stem == NULL ? 0 : wcslen(stem);

    if (length <= 4) {
        free(stem);
        return 0;
    }
    stem[length - 4] = L'\0';
    char *stem_utf8 = narrow(stem);
    free(stem);
    if (stem_utf8 == NULL) return 0;

    memcpy(text, config, strlen(config) + 1);
    int parsed = fledge_parse_config(text, stem_utf8, same_program_name, &program, &problem);
    free(stem_utf8);
    if (parsed != 0) return 0;

    wchar_t *relative = wide(program.entry);
    if (relative == NULL) return 0;
    for (wchar_t *letter = relative; *letter != L'\0'; letter++) {
        if (*letter == L'/') *letter = L'\\';
    }
    wchar_t *entry_path = join(root, L"\\app\\", relative);
    free(relative);
    int found = entry_path != NULL && identify(entry_path, &entry) && same_file(&entry, script);
    free(entry_path);
    return found;
}

/* The path of the launcher in root that runs script, as a new string,
 * or NULL. */
static wchar_t *
find_launcher(const wchar_t *root, const char *config, const struct identity *script)
{
    wchar_t *pattern = join(root, L"\\*.exe", L"");
    wchar_t *long_pattern = pattern == NULL ? NULL : long_form(pattern);
    WIN32_FIND_DATAW item;
    wchar_t *found = NULL;

    free(pattern);
    if (long_pattern == NULL) return NULL;
    HANDLE search = FindFirstFileExW(long_pattern, FindExInfoBasic, &item, FindExSearchNameMatch, NULL, 0);
    free(long_pattern);
    if (search == INVALID_HANDLE_VALUE) return NULL;
    do {
        if ((item.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0) continue;
        size_t length = wcslen(item.cFileName);
        /* *.exe also matches a short name, such as LONGNA~1.EXE for
         * LongName.exeX; only a name that ends in .exe is a program. */
        if (length <= 4 || CompareStringOrdinal(item.cFileName + length - 4, 4, L".exe", 4, TRUE) != CSTR_EQUAL)
            continue;
        if (!runs_script(root, item.cFileName, config, script)) continue;

        wchar_t *path = join(root, L"\\", item.cFileName);
        if (path != NULL && holds_mark(path)) {
            found = path;
        } else {
            free(path);
        }
    } while (found == NULL && FindNextFileW(search, &item));
    FindClose(search);
    return found;
}

static int
is_space(wchar_t letter)
{
    return letter == L' ' || letter == L'\t' || letter == L'\n' || letter == L'\v' || letter == L'\f' ||
           letter == L'\r';
}

/*
 * Skips the spaces before the argument at text, and the argument, when
 * Ruby's join_argv could have written it: plain, with no quote, or in
 * double quotes with no quote inside, and, when plain_name is nonzero,
 * with no character of a file name pattern. Returns what follows it, or
 * NULL when the argument is not so written, or there is none.
 */
static const wchar_t *
skip_argument(const wchar_t *text, int plain_name)
{
    while (is_space(*text)) text++;
    if (*text == L'\0') return NULL;

    const wchar_t *end = text;
    if (*text == L'"') {
        end = wcschr(text + 1, L'"');
        if (end == NULL) return NULL;
        end++;
        if (*end != L'\0' && !is_space(*end)) return NULL;
    } else {
        while (*end != L'\0' && !is_space(*end)) end++;
    }
    for (const wchar_t *letter = text; letter < end; letter++) {
        if (*letter == L'\'' || (*letter == L'"' && letter != text && letter != end - 1)) return NULL;
        if (plain_name && wcschr(L"*?[{", *letter) != NULL) return NULL;
    }
    return end;
}

/* Writes message, "ruby: " and words that follow it in UTF-8, to standard
 * error: as UTF-16 to a console, and as UTF-8 to a file or pipe. */
static void
complain(const char *message)
{
    HANDLE error = GetStdHandle(STD_ERROR_HANDLE);
    DWORD mode;
    DWORD written;
    wchar_t *text = wide(message);

    if (error == NULL || error == INVALID_HANDLE_VALUE) {
        free(text);
        return;
    }
    if (text != NULL && GetConsoleMode(error, &mode)) {
        WriteConsoleW(error, text, (DWORD)wcslen(text), &written, NULL);
    } else {
        WriteFile(error, message, (DWORD)strlen(message), &written, NULL);
    }
    free(text);
}

/* Keeps Ctrl-C and Ctrl-Break from ending ruby.exe while the launcher,
 * which shares its console and gets the same event, decides what they
 * do, as CPython's py launcher does (PC/launcher.c, ctrl_c_handler). A
 * handler, unlike SetConsoleCtrlHandler(NULL, TRUE), is not inherited by
 * the launcher. */
static BOOL WINAPI
leave_to_the_launcher(DWORD event)
{
    return event == CTRL_C_EVENT || event == CTRL_BREAK_EVENT;
}

/* Runs launcher with the command line rest, waits for it, and exits
 * with its status. Exits with EX_SOFTWARE when it cannot start it. */
static void __attribute__((noreturn))
run_launcher(const wchar_t *launcher, const wchar_t *rest)
{
    static const char failure[] = "ruby: could not run ";
    wchar_t *command = join(L"\"", launcher, L"\"");
    wchar_t *line = command == NULL ? NULL : join(command, rest, L"");
    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    DWORD error = ERROR_NOT_ENOUGH_MEMORY;

    free(command);
    memset(&startup, 0, sizeof startup);
    startup.cb = sizeof startup;
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    SetConsoleCtrlHandler(leave_to_the_launcher, TRUE);
    if (line != NULL && CreateProcessW(launcher, line, NULL, NULL, TRUE, 0, NULL, NULL, &startup, &process)) {
        DWORD status = FLEDGE_EXIT_SOFTWARE;

        CloseHandle(process.hThread);
        WaitForSingleObject(process.hProcess, INFINITE);
        if (!GetExitCodeProcess(process.hProcess, &status)) status = FLEDGE_EXIT_SOFTWARE;
        CloseHandle(process.hProcess);
        ExitProcess(status);
    }
    if (line != NULL) error = GetLastError();

    char *path = narrow(launcher);
    char message[sizeof failure + 4096];
    snprintf(message, sizeof message, "%s%s: Windows error %lu\r\n", failure,
             path == NULL ? "the app's launcher" : path, (unsigned long)error);
    free(path);
    complain(message);
    ExitProcess(FLEDGE_EXIT_SOFTWARE);
}

void
fledge_limit_dll_search(void)
{
    wchar_t *program = own_path();
    wchar_t *slash = program == NULL ? NULL : wcsrchr(program, L'\\');

    if (!SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS) || slash == NULL) {
        free(program);
        return;
    }
    *slash = L'\0';
    wchar_t *builtin = join(program, L"\\ruby_builtin_dlls", L"");
    if (builtin != NULL && AddDllDirectory(builtin) == NULL && GetLastError() == ERROR_FILENAME_EXCED_RANGE) {
        wchar_t *long_path = long_form(builtin);
        if (long_path != NULL) AddDllDirectory(long_path);
        free(long_path);
    }
    free(builtin);
    free(program);
}

void
fledge_relaunch(int argc, char **argv)
{
    static char config[CONFIG_SIZE];
    struct identity script;

    if (argc < 2 || argv[1][0] == '-' || argv[1][0] == '\0') return;

    const wchar_t *rest = skip_argument(GetCommandLineW(), 0);
    if (rest != NULL) rest = skip_argument(rest, 1);
    if (rest == NULL) return;

    wchar_t *script_path = wide(argv[1]);
    int is_file = script_path != NULL && identify(script_path, &script);
    free(script_path);
    if (!is_file) return;

    /* ruby.exe is ROOT\ruby\bin\ruby.exe. */
    wchar_t *root = own_path();
    for (int level = 0; root != NULL && level < 3; level++) {
        wchar_t *slash = wcsrchr(root, L'\\');
        if (slash == NULL) {
            free(root);
            return;
        }
        *slash = L'\0';
    }
    if (root == NULL) return;

    wchar_t *config_path = join(root, L"\\" FLEDGE_CONFIG, L"");
    int readable = config_path != NULL && read_config(config_path, config) == 0;
    free(config_path);
    wchar_t *launcher = readable ? find_launcher(root, config, &script) : NULL;
    free(root);
    if (launcher != NULL) run_launcher(launcher, rest);
}
