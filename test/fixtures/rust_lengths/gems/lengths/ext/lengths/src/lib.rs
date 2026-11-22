// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT-0

//! The extension of test/fixtures/rust_lengths, on rb-sys's bindings
//! alone: the width they give rb_len_t, and two calls whose results
//! differ when that width is not Ruby's, one that passes a negative
//! length and one that returns lengths through pointers.

use rb_sys::*;
use std::mem::{size_of, transmute};

/// The bytes of rb_len_t, as these bindings declare it.
unsafe extern "C" fn width(_module: VALUE) -> VALUE {
    rb_int2inum(size_of::<rb_len_t>() as isize)
}

/// The element of `array` at -1, which Ruby finds only if the -1 reaches
/// it as the width it reads.
unsafe extern "C" fn last(_module: VALUE, array: VALUE) -> VALUE {
    rb_ary_entry(array, -1)
}

/// Two lengths, each with a canary right after it, which Ruby's write
/// of a wider length than the bindings declare reaches.
#[repr(C)]
struct Span {
    beginning: rb_len_t,
    after_beginning: u32,
    length: rb_len_t,
    after_length: u32,
}

const CANARY: u32 = 0x7eadbeef;

/// The beginning and length rb_range_beg_len gives for `range` over
/// `total` elements, and whether both canaries are as they were.
unsafe extern "C" fn span(_module: VALUE, range: VALUE, total: VALUE) -> VALUE {
    let mut span = Span { beginning: 0, after_beginning: CANARY, length: 0, after_length: CANARY };
    rb_range_beg_len(range, &mut span.beginning, &mut span.length, rb_num2long(total) as rb_len_t, 1);
    let whole = span.after_beginning == CANARY && span.after_length == CANARY;
    let result = rb_ary_new();
    rb_ary_push(result, rb_int2inum(span.beginning as isize));
    rb_ary_push(result, rb_int2inum(span.length as isize));
    rb_ary_push(result, if whole { Qtrue as VALUE } else { Qfalse as VALUE });
    result
}

#[allow(non_snake_case)]
#[no_mangle]
pub extern "C" fn Init_lengths() {
    unsafe {
        let module = rb_define_module(c"Lengths".as_ptr());
        let width = transmute::<unsafe extern "C" fn(VALUE) -> VALUE, unsafe extern "C" fn() -> VALUE>(width);
        let last = transmute::<unsafe extern "C" fn(VALUE, VALUE) -> VALUE, unsafe extern "C" fn() -> VALUE>(last);
        let span = transmute::<unsafe extern "C" fn(VALUE, VALUE, VALUE) -> VALUE, unsafe extern "C" fn() -> VALUE>(span);
        rb_define_module_function(module, c"width".as_ptr(), Some(width), 0);
        rb_define_module_function(module, c"last".as_ptr(), Some(last), 1);
        rb_define_module_function(module, c"span".as_ptr(), Some(span), 2);
    }
}
