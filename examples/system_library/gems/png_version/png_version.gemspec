# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

Gem::Specification.new do |spec|
  spec.name = "png_version"
  spec.version = "1.0.0"
  spec.authors = ["Kerrick Long"]
  spec.summary = "A path gem whose C extension links the Linux distribution's libpng, in examples/system_library"
  spec.license = "MIT-0"
  spec.files = ["lib/png_version.rb", "ext/png_version/extconf.rb", "ext/png_version/png_version.c"]
  spec.extensions = ["ext/png_version/extconf.rb"]
end
