/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */
#include <greet.h>
#include <ruby.h>

/* What libgreet answers, which it asks libpunct to finish. */
static VALUE
hello(VALUE self)
{
    (void)self;
    return rb_str_new_cstr(greet_hello());
}

void
Init_greet(void)
{
    rb_define_singleton_method(rb_define_module("Greet"), "hello", hello, 0);
}
