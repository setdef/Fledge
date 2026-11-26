# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "zlib"
require "digest/sha1"

module Basket
  module Android
    # A dex file of one class, written in Ruby: a public class NAME that
    # implements java.lang.reflect.InvocationHandler, with a public
    # constructor that calls Object's, and the interface's one method,
    # invoke, declared native, so that RegisterNatives can give it code.
    # Version 035, its ids sorted, as ART's DexFileVerifier requires.
    module Dex
      # The JNI descriptor of Object.
      OBJECT = "Ljava/lang/Object;"
      # The descriptor of the interface the class implements.
      HANDLER = "Ljava/lang/reflect/InvocationHandler;"
      # The descriptor of Method, which +invoke+ takes.
      METHOD = "Ljava/lang/reflect/Method;"
      # The descriptor of an array of Object, which +invoke+ takes.
      OBJECTS = "[Ljava/lang/Object;"
      # What a dex file writes for "no index", such as a class with no
      # superclass source file.
      NO_INDEX = 0xffffffff

      # +value+ as dex's unsigned LEB128, seven bits to a byte.
      def self.uleb(value)
        bytes = +"".b
        loop do
          byte = value & 0x7f
          value >>= 7
          bytes << (value.zero? ? byte : byte | 0x80)
          return bytes if value.zero?
        end
      end

      # The bytes of a dex file of the class +name+ (a Java name such as
      # "basket.Handler").
      def self.handler_class(name)
        descriptor = "L#{name.tr('.', '/')};"
        strings = ["<init>", "LLLL", descriptor, OBJECT, HANDLER, METHOD, "V", OBJECTS, "invoke"].sort
        s = -> (text) { strings.index(text) }
        types = [descriptor, OBJECT, HANDLER, METHOD, "V", OBJECTS].sort_by { |t| s[t] }
        t = -> (text) { types.index(text) }
        # proto 0: (Object, Method, Object[]) Object; proto 1: ()V
        protos = [[s["LLLL"], t[OBJECT], [t[OBJECT], t[METHOD], t[OBJECTS]]], [s["V"], t["V"], []]]
        protos.sort_by! { |shorty, ret, params| [ret, params] }
        invoke_proto = protos.index { |p| p[1] == t[OBJECT] }
        init_proto = protos.index { |p| p[1] == t["V"] }
        methods = [[t[descriptor], init_proto, s["<init>"]], [t[descriptor], invoke_proto, s["invoke"]], [t[OBJECT], init_proto, s["<init>"]]]
        methods.sort_by! { |klass, proto, name_idx| [klass, name_idx, proto] }
        m_init = methods.index([t[descriptor], init_proto, s["<init>"]])
        m_invoke = methods.index([t[descriptor], invoke_proto, s["invoke"]])
        m_object_init = methods.index([t[OBJECT], init_proto, s["<init>"]])

        header_size = 0x70
        string_ids_off = header_size
        type_ids_off = string_ids_off + (strings.size * 4)
        proto_ids_off = type_ids_off + (types.size * 4)
        method_ids_off = proto_ids_off + (protos.size * 12)
        class_defs_off = method_ids_off + (methods.size * 8)
        data_off = class_defs_off + 32

        data = +"".b
        align = -> (n) { data << ("\0" * ((-(data_off + data.bytesize)) % n)) }
        here = -> { data_off + data.bytesize }

        # code_item of <init>: invoke-direct {v0}, Object.<init>; return-void
        align[4]
        code_off = here[]
        data << [1, 1, 1, 0, 0, 4].pack("vvvvVV")
        data << [0x1070, m_object_init, 0x0000, 0x000e].pack("vvvv")

        # type_lists: the interfaces, and invoke's parameters
        align[4]
        interfaces_off = here[]
        data << [1, t[HANDLER]].pack("Vv")
        align[4]
        params_off = here[]
        data << [3, t[OBJECT], t[METHOD], t[OBJECTS]].pack("Vvvv")

        string_data_offs = strings.map do |text|
          off = here[]
          data << uleb(text.size) << text.b << "\0"
          off
        end

        class_data_off = here[]
        data << uleb(0) << uleb(0) << uleb(1) << uleb(1)
        data << uleb(m_init) << uleb(0x10001) << uleb(code_off)
        data << uleb(m_invoke) << uleb(0x0101) << uleb(0)

        align[4]
        map_off = here[]
        map = [
          [0x0000, 1, 0],
          [0x0001, strings.size, string_ids_off],
          [0x0002, types.size, type_ids_off],
          [0x0003, protos.size, proto_ids_off],
          [0x0005, methods.size, method_ids_off],
          [0x0006, 1, class_defs_off],
          [0x2001, 1, code_off],
          [0x1001, 2, interfaces_off],
          [0x2002, strings.size, string_data_offs.first],
          [0x2000, 1, class_data_off],
          [0x1000, 1, map_off],
        ]
        data << [map.size].pack("V")
        map.each { |type, size, off| data << [type, 0, size, off].pack("vvVV") }

        body = +"".b
        body << string_data_offs.pack("V*")
        body << types.map { |text| s[text] }.pack("V*")
        protos.each { |shorty, ret, params| body << [shorty, ret, params.empty? ? 0 : params_off].pack("VVV") }
        methods.each { |klass, proto, name_idx| body << [klass, proto, name_idx].pack("vvV") }
        body << [t[descriptor], 1, t[OBJECT], interfaces_off, NO_INDEX, 0, class_data_off, 0].pack("V8")
        body << data
        file_size = header_size + body.bytesize

        header = +"dex\n035\0".b
        header << [0].pack("V") << ("\0" * 20)
        header << [
          file_size,
          header_size,
          0x12345678,
          0,
          0,
          map_off,
          strings.size,
          string_ids_off,
          types.size,
          type_ids_off,
          protos.size,
          proto_ids_off,
          0,
          0,
          methods.size,
          method_ids_off,
          1,
          class_defs_off,
          file_size - data_off,
          data_off,
].pack("V*")
        dex = header + body
        dex[12, 20] = Digest::SHA1.digest(dex[32..])
        dex[8, 4] = [Zlib.adler32(dex[12..])].pack("V")
        dex
      end
    end
  end
end
