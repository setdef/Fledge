/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT-0
 */
#include <ruby.h>

static VALUE greet(VALUE self) { return rb_str_new_cstr("greeter compiled for the runtime's Ruby"); }

void Init_greeter(void) { rb_define_singleton_method(rb_define_module("Greeter"), "greet", greet, 0); }
