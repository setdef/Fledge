/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT-0
 */
#include <png.h>
#include <ruby.h>

/* The version of the libpng the loader loaded, which is the computer's. */
static VALUE
libpng(VALUE self)
{
    (void)self;
    return rb_str_new_cstr(png_get_libpng_ver(NULL));
}

void
Init_png_version(void)
{
    rb_define_singleton_method(rb_define_module("PngVersion"), "libpng", libpng, 0);
}
