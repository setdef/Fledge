# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/deb"
require "open3"

# The dependencies of a .deb Fledge::Deb writes (ADR 030), as
# dpkg-shlibdeps finds them for a gem's extension this computer's cc
# compiles. test/deb_test.rb covers the rest of the package.
class DebDependenciesTest < Minitest::Test
  include DebHelpers

  # A gem's extension, compiled here, that needs zlib from the
  # distribution, as a wrapper of a desktop library needs that library.
  # Every Debian and Ubuntu has zlib1g; only its library is needed, not
  # its headers.
  def zlib_extension(dir)
    shlibdeps = system("dpkg-shlibdeps", "--version", out: File::NULL, err: File::NULL)
    compiler = system("cc", "--version", out: File::NULL, err: File::NULL)
    unless shlibdeps && compiler
      message = "a .deb depends on what dpkg-shlibdeps, from Debian's dpkg-dev, finds, here for a file cc compiles"
      ENV["FLEDGE_REQUIRE_DPKG_DEB"] ? flunk(message) : skip(message)
    end
    path = File.join(dir, "wrapper.so")
    source = "const char *zlibVersion(void);\nconst char *wrapper_version(void) { return zlibVersion(); }\n"
    out, status = Open3.capture2e("cc", "-shared", "-fPIC", "-x", "c", "-", "-o", path, "-l:libz.so.1", stdin_data: source)
    assert_predicate status, :success?, out
    path
  end

  # ADR 030: a library fledge.yml lists as the distribution's becomes a
  # dependency on the package that provides it, as dpkg-shlibdeps finds
  # it for the files that need it, beside glibc's, which stays the
  # runtime's. With nothing listed, glibc's stays the only one, whatever
  # the gems' files need.
  def test_a_library_listed_as_the_distributions_is_a_dependency_on_its_package
    need_dpkg_deb
    Dir.mktmpdir do |dir|
      extension = zlib_extension(dir)
      depends = field(build(File.join(dir, "listed").tap { |d| FileUtils.mkdir_p(d) }, extension:, system_libraries: ["libz.so.1"]), "Depends")
      plain = field(build(File.join(dir, "plain").tap { |d| FileUtils.mkdir_p(d) }, extension:), "Depends")

      assert_match(/\Alibc6 \(>= 2\.39\), zlib1g \(>= [^)]+\)\z/, depends)
      assert_equal "libc6 (>= 2.39)", plain
    end
  end
end
