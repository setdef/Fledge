# frozen_string_literal: true

# Probe 162 (a spike, never for trunk): replaces app/main.rb of a built
# Basket, so that the process is Basket.exe's, with Basket's launcher,
# Ruby, and bundle, and reports to the file in PROBE_OUT what WinUI
# does on this computer.

require "fiddle"
require_relative "lib/basket/winrt"
require_relative "lib/basket/winui"

$stdout.sync = true
REPORT = File.open(ENV.fetch("PROBE_OUT"), "w")
REPORT.sync = true

W = Basket::WinRT
Win = W::Win
IID_ACTIVATION_FACTORY = "00000035-0000-0000-c000-000000000046"
MACHINES = { 0x14c => "x86", 0x8664 => "x64", 0xaa64 => "ARM64", 0xa641 => "ARM64EC", 0x1c4 => "ARM" }.freeze
ARCHITECTURES = { 0 => "x86", 5 => "arm", 9 => "x64", 11 => "neutral", 12 => "arm64" }.freeze

def say(text = "")
  REPORT.puts(text)
end

def machine_name(code)
  "#{MACHINES.fetch(code, 'other')} (0x#{code.to_s(16)})"
end

def pe_machine(path)
  File.open(path, "rb") do |file|
    file.seek(0x3c)
    offset = file.read(4).unpack1("V")
    file.seek(offset)
    return "not a PE file" unless file.read(4) == "PE\0\0".b

    machine_name(file.read(2).unpack1("v"))
  end
rescue => e
  "unreadable (#{e.class}: #{e.message})"
end

def current_process
  Win.function("kernel32.dll", "GetCurrentProcess", [], W::POINTER).call
end

def process_machines
  process = Win.buffer(2)
  native = Win.buffer(2)
  hr = Win.function("kernel32.dll", "IsWow64Process2", [W::POINTER, W::POINTER, W::POINTER], W::INT).call(current_process, process, native)
  "IsWow64Process2 returned #{hr}; process machine #{process[0, 2].unpack1('v')} (0 means the native one), native machine #{machine_name(native[0, 2].unpack1('v'))}"
end

def wide_string(address)
  return "(null)" if address.zero?

  pointer = Fiddle::Pointer.new(address)
  text = "".b
  520.times do |i|
    unit = pointer[i * 2, 2]
    break if unit == "\0\0".b

    text << unit
  end
  text.force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8, invalid: :replace)
end

def bstr(address)
  return "" if address.zero?

  bytes = Fiddle::Pointer.new(address - 4)[0, 4].unpack1("L")
  Fiddle::Pointer.new(address)[0, bytes].force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8, invalid: :replace)
end

def modules(label)
  say "-- modules loaded #{label}"
  process = current_process
  needed = Win.buffer(4)
  size = 8 * 2048
  list = Win.buffer(size)
  Win.function("kernel32.dll", "K32EnumProcessModulesEx", [W::POINTER, W::POINTER, W::UINT, W::POINTER, W::UINT], W::INT).call(process, list, size, needed, 3)
  count = [needed[0, 4].unpack1("L") / 8, 2048].min
  name = Win.buffer(1040)
  file_name = Win.function("kernel32.dll", "K32GetModuleFileNameExW", [W::POINTER, W::POINTER, W::POINTER, W::UINT], W::UINT)
  count.times do |i|
    handle = list[i * 8, 8].unpack1("Q")
    length = file_name.call(process, handle, name, 520)
    path = name[0, length * 2].force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8, invalid: :replace)
    say format("  %-16s %s", pe_machine(path).split.first(2).join(" "), path)
  end
  say "  (#{count} modules)"
end

def package_graph(label)
  say "-- package graph #{label}"
  function = Win.function("kernel32.dll", "GetCurrentPackageInfo", [W::UINT, W::POINTER, W::POINTER, W::POINTER], W::UINT)
  length = Win.buffer(4)
  count = Win.buffer(4)
  status = function.call(0, length, nil, count)
  say "  GetCurrentPackageInfo(ALL_LOADED, size query): #{status}, needs #{length[0, 4].unpack1('L')} bytes, #{count[0, 4].unpack1('L')} packages"
  return unless status == 122

  buffer = Win.buffer(length[0, 4].unpack1("L"))
  status = function.call(0, length, buffer, count)
  say "  GetCurrentPackageInfo(ALL_LOADED): #{status}"
  return unless status.zero?

  count[0, 4].unpack1("L").times do |i|
    base = buffer.to_i + (i * 80)
    info = Fiddle::Pointer.new(base)[0, 80]
    flags = info[4, 4].unpack1("L")
    path, full, = info[8, 24].unpack("QQQ")
    architecture = info[36, 4].unpack1("L")
    version = info[40, 8].unpack1("Q")
    numbers = [version >> 48, (version >> 32) & 0xffff, (version >> 16) & 0xffff, version & 0xffff].join(".")
    say "  #{wide_string(full)} flags 0x#{flags.to_s(16)} architecture #{ARCHITECTURES.fetch(architecture, architecture)} version #{numbers}"
    say "    at #{wide_string(path)}"
  end
end

def restricted_info
  cell = Win.buffer(8)
  hr = Win.function("combase.dll", "GetRestrictedErrorInfo", [W::POINTER], W::INT).call(cell) & 0xffffffff
  pointer = cell[0, 8].unpack1("Q")
  return "GetRestrictedErrorInfo returned 0x#{hr.to_s(16)} and no object" if pointer.zero? || hr >= 0x80000000

  info = W::Interface.new(pointer)
  description = Win.buffer(8)
  error = Win.buffer(8)
  restricted = Win.buffer(8)
  sid = Win.buffer(8)
  info.call(3, [W::POINTER] * 4, description, error, restricted, sid)
  reference = Win.buffer(8)
  info.call(4, [W::POINTER], reference)
  "error 0x#{error[0, 4].unpack1('L').to_s(16)}, description #{bstr(description[0, 8].unpack1('Q')).inspect}, restricted description #{bstr(restricted[0, 8].unpack1('Q')).inspect}, reference #{bstr(reference[0, 8].unpack1('Q')).inspect}"
end

def clear_restricted_info
  Win.function("combase.dll", "SetRestrictedErrorInfo", [W::POINTER], W::INT).call(nil)
end

def attempt(label)
  clear_restricted_info
  yield
  say "#{label}: succeeded"
  true
rescue W::Error, Fiddle::DLError => e
  say "#{label}: #{e.class}: #{e.message}"
  say "    restricted error info: #{restricted_info}"
  false
end

class << W
  # Prints the two calls that give this process the framework package,
  # as Basket makes them, with their results.
  def add_framework
    id = Win.buffer(8)
    architecture = RUBY_PLATFORM.match?(/aarch64|arm64/) ? W::ARM64 : W::X64
    create = Win.function("kernelbase.dll", "TryCreatePackageDependency", [W::POINTER, W::POINTER, W::INT64, W::INT, W::INT, W::POINTER, W::INT, W::POINTER], W::INT)
    add = Win.function("kernelbase.dll", "AddPackageDependency", [W::POINTER, W::INT, W::INT, W::POINTER, W::POINTER], W::INT)
    hr = create.call(nil, Win.wide(W::FRAMEWORK), W::FRAMEWORK_VERSION, architecture, 0, nil, 0, id) & 0xffffffff
    say "TryCreatePackageDependency(#{W::FRAMEWORK}, minimum 0x#{W::FRAMEWORK_VERSION.to_s(16)}, architectures 0x#{architecture.to_s(16)}): 0x#{hr.to_s(16)}"
    return false if hr >= W::FAILED

    say "  its dependency id: #{wide_string(id[0, 8].unpack1('Q'))}"
    full = Win.buffer(8)
    hr = add.call(id[0, 8].unpack1("Q"), 0, 0, Win.buffer(8), full) & 0xffffffff
    say "AddPackageDependency: 0x#{hr.to_s(16)}, resolved package #{wide_string(full[0, 8].unpack1('Q'))}"
    hr < W::FAILED
  end

  # What OnLaunched does in Basket, with every step reported.
  def on_launched(&)
    begin
      Probe.run
    rescue Exception => e # rubocop:disable Lint/RescueException
      say "the probe failed: #{e.class}: #{e.message}"
      e.backtrace.first(8).each { |line| say "    #{line}" }
    end
    begin
      quit
    rescue Exception => e # rubocop:disable Lint/RescueException
      say "quit failed: #{e.class}: #{e.message}"
    end
    0
  end
end

module Probe
  CLASSES = %w[
    Microsoft.UI.Xaml.Controls.XamlControlsResources
    Microsoft.UI.Xaml.ResourceDictionary
    Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider
    Microsoft.UI.Xaml.Window
    Microsoft.UI.Xaml.Controls.Button
    Microsoft.UI.Xaml.Controls.TextBox
    Microsoft.UI.Xaml.Controls.ListView
    Microsoft.UI.Xaml.Controls.Grid
  ].freeze
  NS = 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'

  def self.run
    say "-- in OnLaunched"
    package_graph("in OnLaunched")
    modules("in OnLaunched, before any activation")
    2.times do |round|
      say "-- round #{round + 1}"
      CLASSES.each do |name|
        attempt("RoGetActivationFactory #{name}") { W.factory(name, IID_ACTIVATION_FACTORY) }
        attempt("RoActivateInstance #{name}") { W.activate(name) }
      end
    end
    activation_factory_call
    reader = W.factory("Microsoft.UI.Xaml.Markup.XamlReader", Basket::WinUI::IID_XAML_READER_STATICS)
    attempt("XamlReader.Load of a Button") { reader.out_object(6, [W::POINTER], Win.hstring("<Button #{NS} Content=\"x\"/>"), what: "XamlReader.Load") }
    attempt("XamlReader.Load of an empty ResourceDictionary") { reader.out_object(6, [W::POINTER], Win.hstring("<ResourceDictionary #{NS}/>"), what: "XamlReader.Load") }
    attempt("XamlReader.Load of a Button with a ThemeResource") { reader.out_object(6, [W::POINTER], Win.hstring("<Button #{NS} Background=\"{ThemeResource SystemAccentColor}\"/>"), what: "XamlReader.Load") }
    package_graph("after the activations")
    modules("after the activations")
  end

  # IActivationFactory::ActivateInstance of XamlControlsResources, called
  # on its factory, whose HRESULT RoActivateInstance gives as it is.
  def self.activation_factory_call
    factory = W.factory("Microsoft.UI.Xaml.Controls.XamlControlsResources", IID_ACTIVATION_FACTORY)
    clear_restricted_info
    cell = Win.buffer(8)
    hr = factory.call(6, [W::POINTER], cell) & 0xffffffff
    say "IActivationFactory::ActivateInstance of XamlControlsResources: 0x#{hr.to_s(16)}"
    say "    restricted error info: #{restricted_info}" if hr >= W::FAILED
  rescue W::Error, Fiddle::DLError => e
    say "IActivationFactory::ActivateInstance of XamlControlsResources: #{e.message}"
  end
end

begin
  say "RUBY_PLATFORM #{RUBY_PLATFORM}; RUBY_DESCRIPTION #{RUBY_DESCRIPTION}"
  say "ENV PROCESSOR_ARCHITECTURE=#{ENV['PROCESSOR_ARCHITECTURE']} PROCESSOR_ARCHITEW6432=#{ENV['PROCESSOR_ARCHITEW6432']}"
  say process_machines
  say "process id #{Process.pid}, executable #{Gem.ruby}"
  package_graph("at the start")
  modules("at the start")
  say "framework_active? before add_framework: #{W.framework_active?}"
  say "WinRT.available?: #{W.available?}"
  package_graph("after available?")
  modules("after available?")
  W.start {}
  say "WinRT.start returned"
rescue Exception => e # rubocop:disable Lint/RescueException
  say "the probe ended with #{e.class}: #{e.message}"
  e.backtrace.first(8).each { |line| say "    #{line}" }
end
REPORT.close
exit 0
