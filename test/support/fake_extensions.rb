# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"

# An app's gems' extensions as Fledge::MobileExtensions gives them to a
# phone's project, +built+ (a MobileExtensions::Built), with a linker
# that writes the registration unit it is given where the library goes,
# since only the NDK links a real one, which
# test/integration/mobile_extensions_build_test.rb does.
class FakeExtensions
  def initialize(built)
    @built = built
  end

  def call(_tree)
    @built
  end

  def shared_library(_built, _build, registration:, into:)
    FileUtils.mkdir_p(File.dirname(into))
    File.write(into, File.read(registration))
    into
  end
end
