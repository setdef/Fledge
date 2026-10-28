# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  # Writes Apple's XML property lists.
  #
  # A macOS app's bundle describes itself in <tt>Info.plist</tt>, and its
  # signature lists the hash of every file in
  # <tt>_CodeSignature/CodeResources</tt>; both are property lists. Ruby's
  # standard library has no writer for them, and Apple's own
  # <tt>plutil</tt> runs only on macOS.
  #
  # This module writes the XML form, as Apple's PropertyList-1.0 DTD
  # defines it and as Apple's tools indent it: a Hash as a +dict+ (with
  # its keys in sorted order, as CoreFoundation writes them), an Array as
  # an +array+, a String as a +string+, an Integer as an +integer+, a
  # Float as a +real+, +true+ and +false+, and Plist::Bytes as +data+ in
  # Base64.
  #
  # Use it to write a bundle's <tt>Info.plist</tt>.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::Plist.write({ "CFBundleName" => "MyCoolApp", "NSHighResolutionCapable" => true })
  #   # => "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist ..."
  #--
  # SPDX-SnippetEnd
  #++
  module Plist
    # Bytes a property list holds as +data+.
    Bytes = Data.define(:bytes)

    # The lines every XML property list begins with.
    HEADER = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
    XML

    # +value+ as an XML property list, in UTF-8.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Plist.write({ "a" => 1 }).include?("<key>a</key>") # => true
    #--
    # SPDX-SnippetEnd
    #++
    def self.write(value)
      out = HEADER.dup
      element(value, 0, out)
      out << "</plist>\n"
    end

    private_class_method def self.element(value, depth, out) # :nodoc:
      indent = "\t" * depth
      case value
      when Hash
        out << "#{indent}<dict>\n"
        value.keys.sort.each do |key|
          out << "#{indent}\t<key>#{escape(key)}</key>\n"
          element(value.fetch(key), depth + 1, out)
        end
        out << "#{indent}</dict>\n"
      when Array
        out << "#{indent}<array>\n"
        value.each { |item| element(item, depth + 1, out) }
        out << "#{indent}</array>\n"
      else
        out << indent << scalar(value) << "\n"
      end
    end

    private_class_method def self.scalar(value) # :nodoc:
      case value
      when true then "<true/>"
      when false then "<false/>"
      when Integer then "<integer>#{value}</integer>"
      when Float then "<real>#{value}</real>"
      when Bytes then "<data>#{[value.bytes].pack('m0')}</data>"
      else "<string>#{escape(value.to_s)}</string>"
      end
    end

    private_class_method def self.escape(text) # :nodoc:
      text.encode(Encoding::UTF_8).gsub(/[&<>]/, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")
    end
  end
end
