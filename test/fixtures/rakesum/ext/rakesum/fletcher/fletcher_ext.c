/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT-0
 */

#include <ruby.h>
#include <stdint.h>

/* Rakesum.fletcher16(string): the Fletcher-16 checksum of the string's bytes. */
static VALUE
fletcher16(VALUE self, VALUE string)
{
    const unsigned char *bytes = (const unsigned char *)RSTRING_PTR(string);
    long length = RSTRING_LEN(string);
    uint16_t a = 0, b = 0;
    for (long i = 0; i < length; i++) {
        a = (uint16_t)((a + bytes[i]) % 255);
        b = (uint16_t)((b + a) % 255);
    }
    return UINT2NUM(((uint32_t)b << 8) | a);
}

void
Init_fletcher_ext(void)
{
    rb_define_module_function(rb_define_module("Rakesum"), "fletcher16", fletcher16, 1);
}
