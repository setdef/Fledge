# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class LicensePolicyTest < Minitest::Test
  def test_takes_the_least_restrictive_alternative_and_the_most_restrictive_part
    expected = {
      "MIT" => :notice_only,
      "Ruby OR BSD-2-Clause" => :notice_only,
      "BSDL" => :notice_only,
      "GPL-1.0-or-later OR Artistic-1.0-Perl" => :notice_only,
      "GPL-3.0-or-later WITH GCC-exception-3.1" => :notice_only,
      "MIT AND MPL-2.0" => :file_level,
      "(MIT OR Apache-2.0) AND Unicode-3.0" => :notice_only,
      "Unicode-DFS-2016" => :notice_only,
      "LGPL-3.0-or-later OR GPL-2.0-or-later" => :shared_library,
      "(MIT OR LGPL-2.1-or-later) AND Apache-2.0" => :notice_only,
      "GPL-2.0-only" => :forbidden,
      "AGPL-3.0-or-later" => :forbidden,
      "GPL-2.0-only WITH Classpath-exception-2.0" => :forbidden,
      "NOASSERTION" => :forbidden,
      "LicenseRef-unknown" => :forbidden,
      "" => :forbidden,
      "(MIT" => :forbidden,
      "MIT)" => :forbidden,
    }

    expected.each { |expression, category| assert_equal category, Fledge::LicensePolicy.category(expression), expression }
    assert_equal :first_party, Fledge::LicensePolicy.category("AGPL-3.0-or-later", first_party: true)
  end

  def test_an_apps_gems_must_be_notice_only
    assert Fledge::LicensePolicy.notice_only?("MIT OR GPL-3.0-only")
    refute Fledge::LicensePolicy.notice_only?("LGPL-2.1-or-later")
    refute Fledge::LicensePolicy.notice_only?("MPL-2.0")
    refute Fledge::LicensePolicy.notice_only?("AGPL-3.0-or-later")
  end

  def test_a_gems_declared_licenses_are_alternatives
    assert_equal "Ruby OR BSD-2-Clause", Fledge::LicensePolicy.gem_license(%w[Ruby BSDL])
    assert_equal "MIT", Fledge::LicensePolicy.gem_license(%w[MIT MIT])
    assert_equal "NOASSERTION", Fledge::LicensePolicy.gem_license([])
  end
end
