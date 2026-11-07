/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: MIT-0
 */
#include "total.h"

#include <ruby.h>

static VALUE
add(VALUE self, VALUE left, VALUE right)
{
    long long sum;
    if (__builtin_add_overflow(NUM2LL(left), NUM2LL(right), &sum)) rb_raise(rb_eRangeError, "the sum is too big for a long long");
    return LL2NUM(sum);
}

/*
 * The numbers go in a buffer of ALLOCV_N's, not ALLOCA_N's: the Array
 * may be any size, and ALLOCV_N moves a large buffer from the C stack to
 * the heap, where Ruby frees it even when NUM2LL raises.
 */
static VALUE
total(VALUE self, VALUE numbers)
{
    Check_Type(numbers, T_ARRAY);
    long count = RARRAY_LEN(numbers);
    VALUE buffer;
    long long *values = ALLOCV_N(long long, buffer, count);
    for (long index = 0; index < count; index++) values[index] = NUM2LL(rb_ary_entry(numbers, index));
    long long sum;
    int fits = adder_total(values, (size_t)count, &sum);
    ALLOCV_END(buffer);
    if (!fits) rb_raise(rb_eRangeError, "the total is too big for a long long");
    return LL2NUM(sum);
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
