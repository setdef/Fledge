# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "fiddle"

module Basket
  module Android
    # The process's Java VM, which every call into Java starts from. JNI
    # defines the function that returns it, JNI_GetCreatedJavaVMs, and
    # Android's libnativehelper.so holds it. Which route reaches that
    # library depends on the Android release, so VM tries each in turn:
    #
    # - From Android 12 (API 31), the library is public, and Fiddle
    #   opens it by name.
    # - On Android 8 to 10 (API 26 to 28), the program itself reaches it,
    #   because the system's own app launcher loaded it for everything it
    #   starts.
    # - On Android 10 and 11 (API 29 and 30), the library sits in a
    #   module that Android keeps out of an app's reach, but the file is
    #   readable and the process has mapped it, so VM finds the function
    #   where the file says it is, at the address the process mapped it
    #   to.
    module VM
      # The function that returns the Java VM.
      NAME = "JNI_GetCreatedJavaVMs"
      # The library that holds it.
      LIBRARY = "libnativehelper.so"

      # The ways to the function, each a method of VM.
      ROUTES = %i[by_name from_the_program from_the_map].freeze

      class << self
        # The Java VM, a pointer.
        def pointer
          @pointer ||= begin
            created = Fiddle::Function.new(function_address, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
            vms = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
            count = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE)
            raise Java::Error, "JNI_GetCreatedJavaVMs found no Java VM" unless created.call(vms, 1, count).zero? && count[0, Fiddle::SIZEOF_INT].unpack1("l") == 1

            vms[0, Fiddle::SIZEOF_VOIDP].unpack1("J")
          end
        end

        # The address of JNI_GetCreatedJavaVMs, by the first route that
        # finds it.
        def function_address
          failures = []
          ROUTES.each do |route|
            return method(route).call
          rescue Fiddle::DLError, SystemCallError, Java::Error => e
            failures << "#{route}: #{e.message}"
          end
          raise Java::Error, "no route reaches #{NAME} (#{failures.join('; ')})"
        end

        private def by_name
          Fiddle.dlopen(LIBRARY)[NAME]
        end

        private def from_the_program
          Fiddle::Handle.new(nil)[NAME]
        end

        # The function's address in the copy of the library that the
        # process has mapped: where /proc/self/maps says the file starts,
        # plus the symbol's value in the file's own .dynsym section.
        private def from_the_map
          mapped = File.readlines("/proc/self/maps").map(&:split).select { |fields| fields[5]&.end_with?("/#{LIBRARY}") }
          raise Java::Error, "#{LIBRARY} is not mapped" if mapped.empty?

          first = mapped.find { |fields| fields[2].to_i(16).zero? } or raise Java::Error, "#{LIBRARY} has no mapping at offset 0"
          elf = File.binread(first[5])
          raise Java::Error, "#{first[5]} is no 64-bit ELF file" unless elf.start_with?("\x7fELF".b) && elf.getbyte(4) == 2

          sections = elf_sections(elf)
          dynsym = sections.find { |section| section[1] == 11 } or raise Java::Error, "#{first[5]} has no .dynsym"
          strings = sections.fetch(dynsym[6])
          (dynsym[5] / 24).times do |index|
            name, _info, _other, _section, value, _size = elf[dynsym[4] + (index * 24), 24].unpack("L<CCS<Q<Q<")
            return first[0].split("-").first.to_i(16) + value if value.positive? && elf[strings[4] + name, NAME.bytesize + 1] == "#{NAME}\0"
          end
          raise Java::Error, "#{first[5]} defines no #{NAME}"
        end

        # The section headers of the 64-bit ELF file +elf+, each as
        # [name, type, flags, address, offset, size, link, info,
        # alignment, entry size].
        private def elf_sections(elf)
          offset = elf[0x28, 8].unpack1("Q<")
          size, count = elf[0x3a, 4].unpack("S<S<")
          Array.new(count) { |index| elf[offset + (index * size), 64].unpack("L<L<Q<Q<Q<Q<L<L<Q<Q<") }
        end
      end
    end
  end
end
