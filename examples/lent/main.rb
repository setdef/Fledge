# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Lent: the things you have lent out, what, to whom, and since when. The
# list shows what is still out, longest first, with how many days each
# has been away, and what came back stays below it.
#
# It is an ordinary Rails app (app/, config/, db/) in a window of its
# own, through Tokra: the window asks for tokra://localhost/, and Tokra
# hands each request to Rails in this process, so nothing listens on any
# port. tokra.conf.json describes the window. The database, the log, and
# the app's secret are in your data folder (lib/data_folder.rb), and the
# database is migrated each time Lent starts, so a newer Lent finds your
# loans as it needs them.
#
#   ruby bin/fetch-gems      (tokra and ferro-url, which no gem server has)
#   bundle install
#   bundle exec ruby main.rb

# Lent has the one environment, and config/application.rb is its file.
ENV["RAILS_ENV"] = "production"
require_relative "config/application"
Rails.application.initialize!

# Active Record looks for db/migrate in the folder Lent started in, as
# bin/rails, which starts in the app's root, can; Lent starts anywhere.
ActiveRecord::Migrator.migrations_paths = Rails.application.paths["db/migrate"].to_a
ActiveRecord::Migration.verbose = false
ActiveRecord::Base.connection_pool.migration_context.migrate

require "tokra"
Rack::Handler::Tokra.run(Rails.application)
