# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Builds tasks with a project's own Gradle wrapper, for a workflow step:
#
#   ruby .github/scripts/gradle.rb PROJECT_DIR TASK...
#
# It runs the one method that holds the rule for a second try, which
# some CI runners need when Maven Central answers 404 for a file it
# holds (MobileParity::Android.gradle_with_a_second_try; issue 27), so
# that no workflow runs a bare ./gradlew. The build's --info log is
# PROJECT_DIR's build/gradle.log, or $RUNNER_TEMP's when it is set.
require_relative "../../tasks/mobile_parity"

project, *tasks = ARGV
abort "usage: ruby .github/scripts/gradle.rb PROJECT_DIR TASK..." if project.nil? || tasks.empty?

log = File.join(ENV.fetch("RUNNER_TEMP", File.join(project, "build")), "gradle-#{File.basename(File.expand_path(project)).tr(' ', '-')}.log")
exit(MobileParity::Android.gradle(File.expand_path(project), *tasks, log:) ? 0 : 1)
