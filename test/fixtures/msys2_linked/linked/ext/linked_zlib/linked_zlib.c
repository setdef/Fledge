/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT-0
 */

#include <ruby.h>
#include <zlib.h>

/* LinkedZlib.crc32(string): zlib's CRC-32 of the string's bytes. */
static VALUE
linked_crc32(VALUE self, VALUE string)
{
    StringValue(string);
    return ULONG2NUM(crc32(0L, (const Bytef *)RSTRING_PTR(string), (uInt)RSTRING_LEN(string)));
}

void
Init_linked_zlib(void)
{
    rb_define_module_function(rb_define_module("LinkedZlib"), "crc32", linked_crc32, 1);
}
