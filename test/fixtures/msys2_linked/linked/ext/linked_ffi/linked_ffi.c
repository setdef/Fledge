/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT-0
 */

#include <ruby.h>
#include <ffi.h>

static int
add(int a, int b)
{
    return a + b;
}

/* LinkedFfi.add(a, b): a + b, called through libffi's ffi_call. */
static VALUE
linked_add(VALUE self, VALUE a, VALUE b)
{
    ffi_cif cif;
    ffi_type *types[2] = { &ffi_type_sint, &ffi_type_sint };
    int left = NUM2INT(a), right = NUM2INT(b);
    void *values[2] = { &left, &right };
    ffi_arg result;

    if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 2, &ffi_type_sint, types) != FFI_OK) {
        rb_raise(rb_eRuntimeError, "ffi_prep_cif failed");
    }
    ffi_call(&cif, FFI_FN(add), &result, values);
    return INT2NUM((int)result);
}

void
Init_linked_ffi(void)
{
    rb_define_module_function(rb_define_module("LinkedFfi"), "add", linked_add, 2);
}
