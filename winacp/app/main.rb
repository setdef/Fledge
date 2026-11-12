# winacp probe: what activeCodePage changes for the process that runs it.
require "fiddle"
k = Fiddle.dlopen("kernel32.dll")
crt = Fiddle.dlopen("api-ms-win-crt-locale-l1-1-0.dll")
call = ->(lib, name) { Fiddle::Function.new(lib[name], [], Fiddle::TYPE_INT).call }
setlocale = Fiddle::Function.new(crt["setlocale"], [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
binary = begin
  Dir.children(ARGV[1], encoding: Encoding::BINARY).map(&:inspect)
rescue StandardError => e
  e.class.name
end
facts = {
  "exe" => "#{File.basename(RbConfig.ruby)} / #{$0}",
  "GetACP" => call.(k, "GetACP"),
  "GetOEMCP" => call.(k, "GetOEMCP"),
  "GetConsoleCP" => call.(k, "GetConsoleCP"),
  "GetConsoleOutputCP" => call.(k, "GetConsoleOutputCP"),
  "AreFileApisANSI" => call.(k, "AreFileApisANSI"),
  "setlocale(LC_CTYPE)" => setlocale.call(2, nil).to_s,
  "Encoding.locale_charmap" => Encoding.locale_charmap,
  "Encoding.find('locale')" => Encoding.find("locale").name,
  "Encoding.find('filesystem')" => Encoding.find("filesystem").name,
  "Encoding.default_external" => Encoding.default_external.name,
  "Time.now.zone (TZ=#{ENV['TZ'].inspect})" => [Time.now.zone, Time.now.zone&.encoding&.name],
  "ENV['WINACP']" => [ENV["WINACP"], ENV["WINACP"]&.encoding&.name],
  "Dir.children(binary)" => binary,
}
out = facts.map { |name, value| "#{name}: #{value.inspect}" }.join("\n")
if ARGV[0] && !ARGV[0].empty?
  File.binwrite(ARGV[0], "#{out}\n")
else
  puts out
end
