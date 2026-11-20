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

  # Run by hand with a commit, the workflow installs that commit in place
  # of the tag, so a release's steps can run before its tag exists
  # (doc/contributors/design/releases.md, "installed.yml"). release.yml
  # must never reach that: it calls with the tag alone, and workflow_call
  # declares no commit, so there inputs.commit is empty.
  def test_release_yml_calls_it_with_the_tag_alone
    triggers = workflow.fetch(true) # Psych reads YAML 1.1's on as true
    release = YAML.safe_load_file(File.join(ROOT, ".github", "workflows", "release.yml"))

    assert_equal %w[tag], triggers.dig("workflow_call", "inputs").keys
    assert_equal %w[tag], release.dig("jobs", "installed", "with").keys
    assert_equal "./.github/workflows/installed.yml", release.dig("jobs", "installed", "uses")
    assert_includes triggers.dig("workflow_dispatch", "inputs").keys, "commit"
    refute triggers.dig("workflow_dispatch", "inputs", "commit", "required"), "a dispatch needs no commit"
  end

  # With inputs.commit empty, each form it takes is what the workflow was
  # without it: a checkout of the tag, an empty COMMIT, a job that runs.
  def test_a_commit_changes_nothing_when_none_is_given
    text = File.read(File.join(ROOT, ".github", "workflows", "installed.yml"))
    forms = text.scan(/\$\{\{([^}]*inputs\.commit[^}]*)\}\}/).flatten.map(&:strip).uniq

    refute_empty forms
    assert_empty forms - ["inputs.commit || inputs.tag", "inputs.commit", "!inputs.commit"], "a form of inputs.commit the tag's run may not reduce to its old self"
    workflow.fetch("jobs").each do |name, job|
      (job["steps"] || []).each do |step|
        ref = step.dig("with", "ref")
        assert_includes [nil, "${{ inputs.commit || inputs.tag }}"], ref, "#{name} checks out #{ref}" if step["uses"].to_s.start_with?("actions/checkout@")
        commit = step.dig("env", "COMMIT")
        assert_includes [nil, "${{ inputs.commit }}"], commit, "#{name}'s COMMIT is #{commit}"
        step["run"].to_s.lines.grep(/COMMIT/).each do |line|
          assert_match(/\A\s*(\[ -z "\$COMMIT" \] \|\| |.*\$\{COMMIT:-\$TAG\}|.*-e COMMIT\b)/, line, "#{name} uses COMMIT unguarded")
        end
      end
    end
  end

  def test_given_a_commit_each_job_installs_it_in_place_of_the_tag
    JOBS.each do |job|
      step = steps(job).find { |run| run.include?('gem "fledge"') }

      assert_includes step, %(GEMFILE\n  [ -z "$COMMIT" ] || { sed "s|tag: \\"$TAG\\"|ref: \\"$COMMIT\\"|" "$folder/Gemfile" > "$folder/Gemfile.commit" && ) +
        %(mv "$folder/Gemfile.commit" "$folder/Gemfile"; }\n), "#{job} installs no commit"
    end
    assert_equal "${{ !inputs.commit }}", workflow.dig("jobs", "package-managers", "if"), "the recipes' job, which installs the tag, runs with a commit"
  end

  private def workflow
    YAML.safe_load_file(File.join(ROOT, ".github", "workflows", "installed.yml"))
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
