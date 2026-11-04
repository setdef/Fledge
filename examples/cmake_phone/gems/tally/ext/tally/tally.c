/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: MIT-0
 */
#include "tally.h"

#include <ruby.h>

static VALUE
sum(VALUE self, VALUE numbers)
{
    Check_Type(numbers, T_ARRAY);
    long count = RARRAY_LEN(numbers);
    long long *values = ALLOCA_N(long long, count);
    for (long index = 0; index < count; index++) values[index] = NUM2LL(rb_ary_entry(numbers, index));
    return LL2NUM(tally_sum(values, (size_t)count));
}

static VALUE
built_for(VALUE self)
{
    return rb_str_new_cstr(tally_built_for());
}

void
Init_tally(void)
{
    VALUE tally = rb_define_module("Tally");
    rb_define_singleton_method(tally, "sum", sum, 1);
    rb_define_singleton_method(tally, "built_for", built_for, 0);
}
