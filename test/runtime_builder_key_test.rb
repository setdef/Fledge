# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/runtime_builder"

# Whether a runtime left in tmp/runtime is reused or built again: the key
# of what it is built from, and the decision it makes, with no build.
class RuntimeBuilderKeyTest < Minitest::Test
  FILES = {
    "runtime/sources.yml" => "ruby: 4.1.0\n",
    "runtime/launcher/main.c" => "int main(void) { return 0; }\n",
    "runtime/audited.yml" => "audited: one\n",
    "tasks/runtime_builder.rb" => "# builder\n",
    "tasks/runtime_builder/linux.rb" => "# linux\n",
    "lib/fledge/version.rb" => "# version\n",
  }.freeze

  def setup
    @root = Dir.mktmpdir
    FILES.each { |name, text| write(name, text) }
    @work = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf([@root, @work])
  end

  def write(name, text)
    path = File.join(@root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def key(describing: "x86_64-linux on x86_64-linux, Fledge 1", toolchain: { "cc --version" => "cc 14" })
    RuntimeBuilder::Key.new(root: @root, describing:, toolchain:)
  end

  def builder
    RuntimeBuilder.new(platform: Fledge::Platform.find("x86_64-linux"), host: Fledge::Platform.find("x86_64-linux"), work: @work)
  end

  # Leaves a runtime in the work folder, as a build does: its files, and
  # the key file.
  def leave_runtime(builder, key)
    [builder.archive_path, *builder.assets.values.map { |name| File.join(@work, name) }].each { |file| File.write(file, "x") }
    File.write(builder.key_path, key.to_json)
  end

  def test_the_same_inputs_make_the_same_key
    assert_equal(key.parts, key.parts)
    assert_nil(key.mismatch(key.to_json))
  end

  def test_a_changed_pin_changes_the_key_and_names_the_pins
    recorded = key.to_json
    write("runtime/sources.yml", "ruby: 4.1.1\n")

    assert_equal("its pins changed since it was built", key.mismatch(recorded))
  end

  def test_a_changed_launcher_source_names_the_runtime_sources
    recorded = key.to_json
    write("runtime/launcher/main.c", "int main(void) { return 1; }\n")

    assert_equal("its runtime sources changed since it was built", key.mismatch(recorded))
  end

  def test_a_changed_build_task_names_the_build_tasks
    recorded = key.to_json
    write("tasks/runtime_builder/linux.rb", "# linux, changed\n")

    assert_equal("its build tasks changed since it was built", key.mismatch(recorded))
  end

  def test_a_changed_library_file_the_build_uses_names_it
    recorded = key.to_json
    write("lib/fledge/version.rb", "# version 2\n")

    assert_equal("its Fledge's library code changed since it was built", key.mismatch(recorded))
  end

  def test_a_new_file_among_the_inputs_changes_the_key
    recorded = key.to_json
    write("runtime/launcher/extra.c", "\n")

    refute_nil(key.mismatch(recorded))
  end

  def test_the_toolchain_and_the_computer_are_inputs
    recorded = key.to_json

    assert_equal("its toolchain changed since it was built", key(toolchain: { "cc --version" => "cc 15" }).mismatch(recorded))
    assert_equal("its build changed since it was built", key(describing: "x86_64-linux on aarch64-linux, Fledge 1").mismatch(recorded))
  end

  def test_the_record_a_run_of_ci_writes_is_not_an_input
    recorded = key.to_json
    write("runtime/audited.yml", "audited: two\n")

    assert_nil(key.mismatch(recorded))
  end

  def test_several_changes_are_all_named
    recorded = key.to_json
    write("runtime/sources.yml", "ruby: 4.1.1\n")
    write("tasks/runtime_builder.rb", "# builder 2\n")

    assert_equal("its pins and build tasks changed since it was built", key.mismatch(recorded))
  end

  def test_a_missing_or_unreadable_key_file_is_a_mismatch
    assert_equal("it records no key", key.mismatch(nil))
    assert_equal("it records no key", key.mismatch("not json"))
    assert_equal("it records no key", key.mismatch("{}"))
  end

  def test_a_runtime_built_from_the_same_inputs_is_reused
    builder = self.builder
    leave_runtime(builder, key)

    assert_nil(builder.rebuild_reason(key))
  end

  def test_a_runtime_built_from_other_inputs_is_built_again_and_says_why
    builder = self.builder
    leave_runtime(builder, key)
    write("runtime/sources.yml", "ruby: 4.1.1\n")

    assert_equal("its pins changed since it was built", builder.rebuild_reason(key))
  end

  def test_a_runtime_with_a_file_missing_is_built_again
    builder = self.builder
    leave_runtime(builder, key)
    File.delete(builder.assets.fetch(:sbom).then { |name| File.join(@work, name) })

    assert_match(/spdx\.json is not there\z/, builder.rebuild_reason(key))
  end

  def test_a_folder_with_no_runtime_is_built
    assert_match(/is not there\z/, builder.rebuild_reason(key))
  end

  def test_a_runtime_with_no_key_file_is_built_again
    builder = self.builder
    leave_runtime(builder, key)
    File.delete(builder.key_path)

    assert_equal("it records no key", builder.rebuild_reason(key))
  end

  def test_the_toolchain_probes_name_a_tool_that_is_missing
    found = RuntimeBuilder::Key.toolchain([["no-such-tool-fledge", "--version"]])

    assert_equal({ "no-such-tool-fledge --version" => "not found" }, found)
  end

  def test_each_platform_probes_its_own_toolchain
    probes = -> (name) { RuntimeBuilder::Key.probes(RuntimeBuilder.platform(name), cc: "cc") }

    assert_empty(probes.call("x64-mingw-ucrt"))
    assert_includes(probes.call("ios"), ["xcodebuild", "-version"])
    assert_equal([["rustc", "--version"]], probes.call("android"))
    assert_equal([["cc", "--version"], ["rustc", "--version"]], probes.call("x86_64-linux"))
  end
end
