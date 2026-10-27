# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require "i18n"
require "sqlite3"
require_relative "my_cool_app/version"

# The gem-shaped app Fledge's CI ships to every platform (ADR 005): its
# gemspec names an executable, exe/my_cool_app, and two gems. i18n is
# pure Ruby and needs concurrent-ruby; sqlite3 is a C extension, which
# each platform's app carries precompiled for that platform.
#
# Its greeting goes through both: SQLite stores it, in a database in
# memory, and i18n fills it in. Delivery checks the line it prints
# exactly, so it prints only when both gems load and work on the
# platform the app runs on.
module MyCoolApp
  # The line the app prints, naming the gems it went through.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   MyCoolApp.greeting
  #   # => "MyCoolApp 0.1.0 says hello through i18n 1.15.2 and sqlite3 2.10.2 (SQLite 3.51.0)"
  #--
  # SPDX-SnippetEnd
  #++
  def self.greeting
    database = SQLite3::Database.new(":memory:")
    database.execute("CREATE TABLE greetings (locale TEXT, text TEXT)")
    database.execute("INSERT INTO greetings VALUES (?, ?)", ["en", "%{app} says hello through %{i18n} and %{sqlite3}"])
    text = database.get_first_value("SELECT text FROM greetings WHERE locale = ?", "en")
    database.close

    I18n.backend.store_translations(:en, greeting: text)
    I18n.t(:greeting, locale: :en, app: "MyCoolApp #{VERSION}", i18n: "i18n #{I18n::VERSION}",
      sqlite3: "sqlite3 #{SQLite3::VERSION} (SQLite #{SQLite3::SQLITE_VERSION})")
  end
end
