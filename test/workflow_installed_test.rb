# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# installed.yml, which runs on every published tag, installs Fledge as
# the READMEs tell a developer to: their Gemfile line, with the release's
# tag, in hello's own Gemfile and in a Gemfile of Fledge's own, on every
# platform it builds for. v0.13.0 and v0.14.0 shipped when the README's
# way could build no desktop app, because the workflow wrote a line of
# its own; reading both files here keeps either from changing alone.
class WorkflowInstalledTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # The jobs that install Fledge from the tag: desktops, musl, phones.
  JOBS = %w[installed installed-musl installed-mobile].freeze

  def test_the_readmes_give_one_gemfile_line
    assert_equal readme_md_line, readme_rdoc_line
  end

  def test_each_job_writes_the_readmes_line_into_hellos_gemfile_and_a_folder_of_fledges_own
    line = readme_md_line.sub(/tag: "v[^"]+"/, 'tag: "$TAG"')

    refute_equal readme_md_line, line, "the README's line names no tag"
    JOBS.each do |job|
      step = steps(job).find { |run| run.include?(line) }

      refute_nil step, "#{job} writes no Gemfile with the README's line, #{line}"
      assert_match(%r{for folder in "?\S*examples/hello"? "?\S*project"?; do}, step, "#{job} writes it in hello's folder and in one of Fledge's own")
      assert_equal 1, step.scan('gem "fledge"').size, "#{job} writes a second Gemfile line"
    end
  end

  def test_each_job_builds_hello_from_its_own_folder
    JOBS.each do |job|
      build = steps(job).find { |run| run.match?(%r{cd "?\S*examples/hello"?\n\s*bundle exec fledge build }) }

      refute_nil build, "#{job} does not run fledge build in hello's folder"
    end
  end

  private def readme_md_line
    section = File.read(File.join(ROOT, "README.md"))[/^## Installation\n.*?(?=^## )/m]
    lines = section.scan(/^gem "fledge".*$/)

    assert_equal 1, lines.size, "README.md's Installation shows one Gemfile line"
    lines.first
  end

  private def readme_rdoc_line
    lines = File.read(File.join(ROOT, "README.rdoc")).scan(/^ +(gem "fledge".*)$/).flatten.uniq

    assert_equal 1, lines.size, "README.rdoc shows one Gemfile line"
    lines.first
  end

  private def steps(job)
    workflow = YAML.safe_load_file(File.join(ROOT, ".github", "workflows", "installed.yml"))
    workflow.dig("jobs", job, "steps").filter_map { |step| step["run"] }
  end
end
