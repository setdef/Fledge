# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# The .deb Delivery jobs, and Lent's in the same containers, fetch from
# Ubuntu's and Debian's archives in one step, under
# .github/scripts/apt-update.sh's time limits, and nothing after it
# fetches: an apt-get install a later step ran from a host that stalls
# would have no bound but the job's, and say nothing when it ran into it.
# So the step fetches the lists and every package the job's later steps
# install, the .debs' dependencies among them.
class WorkflowAptTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  DEB_JOBS = %w[delivery-deb-x86_64-linux delivery-deb-aarch64-linux].freeze
  JOBS = [*DEB_JOBS, "delivery-lent-x86_64-linux"].freeze

  def test_the_fetch_step_names_every_package_the_job_installs
    JOBS.each do |job|
      runs = steps(job).filter_map { |step| step["run"] }
      fetch = runs.find { |run| run.start_with?(".github/scripts/apt-update.sh") }

      refute_nil fetch, "#{job} does not fetch with apt-update.sh"
      assert_includes fetch.split, "./delivered/*.deb", "#{job} fetches no .deb's dependencies" if DEB_JOBS.include?(job)
      installed = (runs - [fetch]).flat_map { |run| run.scan(/apt-get install -y -qq ([^\n]+)/).flatten.flat_map(&:split) }

      refute_empty installed
      assert_empty installed - fetch.split, "#{job} installs what its fetch step did not fetch"
    end
  end

  def test_apt_update_fetches_the_packages_it_is_given
    script = File.read(File.join(ROOT, ".github", "scripts", "apt-update.sh"))

    assert_includes script, "apt-get install --download-only"
    assert_match(/^Dir::Cache::Archives /, script, "the packages go where a docker-clean hook deletes them")
  end

  private def steps(job)
    workflow = YAML.safe_load_file(File.join(ROOT, ".github", "workflows", "ci.yml"), aliases: true)
    workflow.dig("jobs", job, "steps")
  end
end
