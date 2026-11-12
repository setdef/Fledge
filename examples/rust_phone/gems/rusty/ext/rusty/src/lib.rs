// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT-0

//! The extension of examples/rust_phone: a sum in Rust, and the system
//! and processor Rust compiled it for, so that the line the app prints
//! shows Cargo built it for the phone.

use magnus::{function, prelude::*, Error, Ruby};

fn sum(numbers: Vec<i64>) -> i64 {
    numbers.iter().sum()
}

fn built_for() -> String {
    format!("{} on {}", std::env::consts::OS, std::env::consts::ARCH)
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let rusty = ruby.define_module("Rusty")?;
    rusty.define_singleton_method("sum", function!(sum, 1))?;
    rusty.define_singleton_method("built_for", function!(built_for, 0))?;
    Ok(())
}
