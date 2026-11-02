/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: MIT-0
 */
#include "total.h"

#include <ruby.h>

static VALUE
add(VALUE self, VALUE left, VALUE right)
{
    return LL2NUM(NUM2LL(left) + NUM2LL(right));
}

static VALUE
total(VALUE self, VALUE numbers)
{
    Check_Type(numbers, T_ARRAY);
    long count = RARRAY_LEN(numbers);
    long long *values = ALLOCA_N(long long, count);
    for (long index = 0; index < count; index++) values[index] = NUM2LL(rb_ary_entry(numbers, index));
    return LL2NUM(adder_total(values, (size_t)count));
}

static VALUE
languages(VALUE self)
{
    return rb_ary_new_from_args(2, rb_str_new_cstr("C"), rb_str_new_cstr("C++"));
}

void
Init_adder(void)
{
    VALUE adder = rb_define_module("Adder");
    rb_define_singleton_method(adder, "add", add, 2);
    rb_define_singleton_method(adder, "total", total, 1);
    rb_define_singleton_method(adder, "languages", languages, 0);
}
