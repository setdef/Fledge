/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT-0
 */
#include <openssl/crypto.h>
#include <openssl/opensslv.h>
#include <openssl/ssl.h>
#include <ruby.h>

/* The OpenSSL the extension was compiled against: its headers' text. */
static VALUE
headers(VALUE self)
{
    (void)self;
    return rb_str_new_cstr(OPENSSL_VERSION_TEXT);
}

/* The OpenSSL the extension runs with: the library's own text. */
static VALUE
library(VALUE self)
{
    (void)self;
    return rb_str_new_cstr(OpenSSL_version(OPENSSL_VERSION));
}

/* Whether the library can make a TLS server's context, as Puma does. */
static VALUE
server_context(VALUE self)
{
    SSL_CTX *context = SSL_CTX_new(TLS_server_method());
    (void)self;
    if (context == NULL) {
        return Qfalse;
    }
    SSL_CTX_free(context);
    return Qtrue;
}

void
Init_ssl_version(void)
{
    VALUE module = rb_define_module("SslVersion");
    rb_define_singleton_method(module, "headers", headers, 0);
    rb_define_singleton_method(module, "library", library, 0);
    rb_define_singleton_method(module, "server_context?", server_context, 0);
}
