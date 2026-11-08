/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT-0
 */
#include "tally.h"

#include <ruby.h>

/*
 * The numbers go in a buffer of ALLOCV_N's, not ALLOCA_N's: the Array
 * may be any size, and ALLOCV_N moves a large buffer from the C stack to
 * the heap, where Ruby frees it even when NUM2LL raises.
 */
static VALUE
sum(VALUE self, VALUE numbers)
{
    Check_Type(numbers, T_ARRAY);
    long count = RARRAY_LEN(numbers);
    VALUE buffer;
    long long *values = ALLOCV_N(long long, buffer, count);
    for (long index = 0; index < count; index++) values[index] = NUM2LL(rb_ary_entry(numbers, index));
    long long total;
    int fits = tally_sum(values, (size_t)count, &total);
    ALLOCV_END(buffer);
    if (!fits) rb_raise(rb_eRangeError, "the sum is too big for a long long");
    return LL2NUM(total);
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
