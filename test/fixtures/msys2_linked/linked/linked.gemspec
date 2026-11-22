# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# A gem compiled from source on Windows against MSYS2's zlib and libffi,
# as rugged and ffi are, so that each extension imports the DLL a
# RubyInstaller Ruby finds in MSYS2's bin folder: libz-1.dll and
# libffi-8.dll. For test/integration/built_app_test.rb.
Gem::Specification.new do |spec|
  spec.name = "linked"
  spec.version = "1.0.0"
  spec.authors = ["Kerrick Long"]
  spec.summary = "Two C extensions that link MSYS2's zlib and libffi, for test/integration/built_app_test.rb"
  spec.license = "MIT-0"
  spec.files = [
    "ext/linked_zlib/extconf.rb",
    "ext/linked_zlib/linked_zlib.c",
    "ext/linked_ffi/extconf.rb",
    "ext/linked_ffi/linked_ffi.c",
  ]
  spec.extensions = ["ext/linked_zlib/extconf.rb", "ext/linked_ffi/extconf.rb"]
end
