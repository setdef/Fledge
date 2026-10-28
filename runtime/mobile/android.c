/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * The Android half of the embedding API: the system log, logcat, where
 * standard output's lines are information and standard error's warnings,
 * as CPython's Android support logs them; and the JNI functions through
 * which org.setdef.fledge.FledgeRuby (runtime/mobile/android/) calls
 * fledge_ruby.h.
 *
 * Java's strings reach C as "modified UTF-8" through GetStringUTFChars,
 * which writes a character outside Unicode's first plane as two
 * three-byte halves, so a path or argument with an emoji in it would not
 * be the bytes Ruby expects. The Java class sends each string as its
 * UTF-8 bytes instead, all of them in one array, each followed by a NUL.
 *
 * And OpenSSL reads no environment variable in an Android app: it reads
 * them only through ossl_safe_getenv, which refuses them in a process
 * whose AT_SECURE is set (crypto/uid.c, OPENSSL_issetugid, at 3.6.5),
 * and every app inherits AT_SECURE from zygote, which Android starts in
 * an SELinux domain of its own. So SSL_CERT_FILE, which serves on iOS,
 * goes unread, and OpenSSL trusts only its compiled-in file, the build
 * machine's. The runtime's library is linked with the linker's own
 * --wrap=X509_get_default_cert_file (tasks/runtime_builder/android.rb),
 * which sends OpenSSL's every call of that function here, so its default
 * file is the runtime's CA certificates, and OpenSSL::X509::
 * DEFAULT_CERT_FILE names them.
 */

#include "fledge_ruby.h"
#include "mobile.h"

#include <android/log.h>
#include <jni.h>
#include <stdlib.h>
#include <string.h>

/* The JNI functions FledgeRuby declares native. */
JNIEXPORT jint JNICALL Java_org_setdef_fledge_FledgeRuby_nativeForwardOutput(JNIEnv *env, jclass type, jbyteArray tag);
JNIEXPORT jint JNICALL Java_org_setdef_fledge_FledgeRuby_nativeRun(JNIEnv *env, jclass type, jbyteArray strings_array,
                                                                   jint argc);

/* OpenSSL's own X509_get_default_cert_file, and the one linked in its place. */
const char *__real_X509_get_default_cert_file(void);
const char *__wrap_X509_get_default_cert_file(void);

const char *
__wrap_X509_get_default_cert_file(void)
{
    const char *certificates = fledge_ruby_certificates();

    return certificates != NULL ? certificates : __real_X509_get_default_cert_file();
}

static char *log_tag;

int
fledge_log_open(const char *tag)
{
    free(log_tag);
    log_tag = strdup(tag);
    return log_tag != NULL ? 0 : -1;
}

void
fledge_log_write(int error, const char *text, size_t length)
{
    __android_log_print(error ? ANDROID_LOG_WARN : ANDROID_LOG_INFO, log_tag, "%.*s", (int)length, text);
}

/*
 * The count strings in the bytes of a Java byte[] (each followed by a
 * NUL), as a new array of pointers into a new copy of the bytes, or NULL
 * when out of memory or when the bytes hold fewer strings.
 */
static char **
strings(JNIEnv *env, jbyteArray array, size_t count)
{
    jsize length = (*env)->GetArrayLength(env, array);
    char *bytes = malloc((size_t)length + 1);
    char **list = calloc(count + 1, sizeof *list);

    if (bytes == NULL || list == NULL) {
        free(bytes);
        free(list);
        return NULL;
    }
    (*env)->GetByteArrayRegion(env, array, 0, length, (jbyte *)bytes);
    bytes[length] = '\0';
    char *next = bytes;
    for (size_t index = 0; index < count; index++) {
        if (next >= bytes + length) {
            free(bytes);
            free(list);
            return NULL;
        }
        list[index] = next;
        next += strlen(next) + 1;
    }
    return list;
}

JNIEXPORT jint JNICALL
Java_org_setdef_fledge_FledgeRuby_nativeForwardOutput(JNIEnv *env, jclass type, jbyteArray tag)
{
    (void)type;
    char **list = strings(env, tag, 1);
    if (list == NULL) return -1;
    int status = fledge_ruby_forward_output(list[0]);
    free(list[0]);
    free(list);
    return status;
}

/*
 * Runs fledge_ruby_run with the strings root, script, and then argc
 * arguments, in that order in the bytes of strings_array. The strings
 * stay allocated, since Ruby keeps ARGV's for as long as the process
 * runs.
 */
JNIEXPORT jint JNICALL
Java_org_setdef_fledge_FledgeRuby_nativeRun(JNIEnv *env, jclass type, jbyteArray strings_array, jint argc)
{
    (void)type;
    if (argc < 0) return FLEDGE_RUBY_SOFTWARE;
    char **list = strings(env, strings_array, (size_t)argc + 2);
    if (list == NULL) return FLEDGE_RUBY_SOFTWARE;
    return fledge_ruby_run(list[0], list[1], argc, list + 2);
}
