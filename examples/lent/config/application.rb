# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "fileutils"
require "securerandom"
require_relative "../lib/data_folder"

# Lent, the Rails app (main.rb).
module Lent
  # A Rails app with no web server: Lent's window asks it for each page
  # (main.rb). What a server's config/environments/production.rb would
  # hold is here, for the one environment Lent runs in.
  class Application < Rails::Application
    config.load_defaults 8.1
    # Rails looks for its root from config.ru, or the folder it started
    # in, and an app is started from anywhere.
    config.root = File.expand_path("..", __dir__)
    config.eager_load = true

    # The database, the log, and the secret, in the person's own data
    # folder (config/database.yml reads it from here).
    config.x.data_folder = DataFolder.for("Lent")
    FileUtils.mkdir_p(config.x.data_folder)

    # A server is given its secret when it is deployed. A desktop app
    # makes its own the first time it starts, in the person's own data
    # folder; on macOS and Linux the file is readable by the person
    # alone (mode 600, which Windows ignores).
    secret = File.join(config.x.data_folder, "secret_key_base")
    File.write(secret, SecureRandom.hex(64), perm: 0o600) unless File.exist?(secret)
    config.secret_key_base = File.read(secret)

    # Nothing but Lent's window reaches it, so there is no host to check.
    config.hosts.clear

    config.logger = ActiveSupport::Logger.new(File.join(config.x.data_folder, "lent.log"))
    config.log_level = :info
  end
end
