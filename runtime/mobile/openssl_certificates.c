/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * OpenSSL's default CA certificates in an Android app, compiled into
 * Ruby's openssl extension, openssl.so, where OpenSSL is linked in.
 *
 * OpenSSL reads no environment variable in an Android app: it reads
 * them only through ossl_safe_getenv, which refuses them in a process
 * whose AT_SECURE is set (crypto/uid.c, OPENSSL_issetugid, at 3.6.5),
 * and every app inherits AT_SECURE from zygote, which Android starts in
 * an SELinux domain of its own. So PORTABLE_RUBY_SSL_CERT_FILE, which
 * openssl.rb sets and OpenSSL reads on iOS, as on a desktop
 * (tasks/runtime_builder/certificates.rb), goes unread by OpenSSL, which
 * would trust only its compiled-in file, the build machine's. The
 * extension is linked with the linker's own
 * --wrap=X509_get_default_cert_file (RubySource.openssl_extconf, in
 * tasks/runtime_builder/ruby_source.rb), which sends OpenSSL's every call
 * of that function here, so its default file is the one that variable
 * names, with getenv, which AT_SECURE does not stop: SSL_CERT_FILE's, or
 * else the runtime's CA certificates (fledge_ruby_certificates, in
 * libfledgeruby.so, which the extension needs), as on a desktop; and
 * OpenSSL::X509::DEFAULT_CERT_FILE names it.
 */

#include <stdlib.h>

/* The runtime's CA certificates (mobile.h), or NULL before the app's Ruby is set up. */
const char *fledge_ruby_certificates(void);

/* OpenSSL's own X509_get_default_cert_file, and the one linked in its place. */
const char *__real_X509_get_default_cert_file(void);
const char *__wrap_X509_get_default_cert_file(void);

const char *
__wrap_X509_get_default_cert_file(void)
{
    const char *named = getenv("PORTABLE_RUBY_SSL_CERT_FILE");
    if (named != NULL && named[0] != '\0') return named;
    const char *certificates = fledge_ruby_certificates();

    return certificates != NULL ? certificates : __real_X509_get_default_cert_file();
}
