# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

module Basket
  module Android
    module Java
      # A method or constructor of a Java class, as the text of Java's
      # Method.toString and Constructor.toString gives it, which their
      # Javadoc specifies: the modifiers, the return type, the class and
      # the name, then the parameter types in parentheses:
      #
      #   public static final void android.os.Looper.loop()
      #   public boolean java.util.ArrayList.add(java.lang.Object)
      #   public android.widget.EditText(android.content.Context)
      #
      # Java's Arrays.toString of a class's getMethods lists them all in
      # one string, so one call into Java finds every overload of every
      # name, and Ruby chooses among them by the arguments it was given.
      class Member < Data.define(:name, :parameters, :returns, :static)
        # The name constructors go by in JNI.
        INIT = "<init>"

        # The JNI letter of each primitive type that Basket passes to Java or reads from it.
        PRIMITIVES = { "boolean" => "Z", "byte" => "B", "int" => "I", "long" => "J", "float" => "F", "void" => "V" }.freeze

        # A method's modifiers and return type, its class and name, and
        # its parameter types.
        METHOD = /((?:[\w$.\[\]]+ )+)[\w$.]+\.([\w$]+)\(([^)]*)\)/

        # A constructor's modifiers and class, and its parameter types.
        CONSTRUCTOR = /(?:[\w$.]+ )*[\w$.]+\(([^)]*)\)/

        # What +text+, the Arrays.toString of a class's methods, lists.
        def self.methods_in(text)
          text.scan(METHOD).map do |words, name, parameters|
            words = words.split
            new(name:, parameters: parameters.split(/,\s*/), returns: words.last, static: words.include?("static"))
          end
        end

        # What +text+, the Arrays.toString of a class's constructors,
        # lists.
        def self.constructors_in(text)
          text.scan(CONSTRUCTOR).map { |(parameters)| new(name: INIT, parameters: parameters.split(/,\s*/), returns: "void", static: false) }
        end

        # The JNI descriptor of the Java type +type+, as Class.getTypeName
        # spells it: <tt>int</tt> is <tt>I</tt>, <tt>java.lang.Object</tt>
        # is <tt>Ljava/lang/Object;</tt>, and <tt>byte[]</tt> is
        # <tt>[B</tt>.
        def self.descriptor(type)
          return type.tr(".", "/") if type.start_with?("[")
          return "[#{descriptor(type.delete_suffix('[]'))}" if type.end_with?("[]")

          PRIMITIVES.fetch(type) { "L#{type.tr('.', '/')};" }
        end

        # The member of +members+ that +arguments+ fit best, or an Error
        # when none fits.
        def self.choose(members, arguments)
          fits = members.filter_map { |member| (cost = member.fit(arguments)) && [cost, member] }
          fits.min_by(&:first)&.last or
            raise(Error, "no #{members.first.name} of Java takes (#{arguments.map(&:class).join(', ')})")
        end

        # How much looser than exact +value+ fits a parameter of +type+:
        # 0 for the type itself, more for a wider one, nil for none. A
        # Ruby Integer is an int or a long, a Float a float, a String a
        # String or a wider type, and nil any object. Anything else is a
        # Java object, which fits when it is an instance of +type+, and
        # never a primitive type, which no object is an instance of.
        def self.cost(type, value)
          case value
          when true, false then (type == "boolean") ? 0 : nil
          when ::Integer then { "int" => 0, "long" => 1 }[type]
          when ::Float then (type == "float") ? 0 : nil
          when ::String then { "java.lang.String" => 0, "java.lang.CharSequence" => 1, "java.lang.Object" => 2 }[type]
          when nil then PRIMITIVES.key?(type) ? nil : 1
          else (!PRIMITIVES.key?(type) && value.respond_to?(:instance_of_type?) && value.instance_of_type?(type)) ? 0 : nil
          end
        end

        # The JNI signature of this member.
        def signature
          "(#{parameters.map { |type| Member.descriptor(type) }.join})#{Member.descriptor(returns)}"
        end

        # The sum of how loosely each of +arguments+ fits its parameter,
        # or nil when the counts differ or one does not fit.
        def fit(arguments)
          return nil unless arguments.size == parameters.size

          parameters.zip(arguments).sum { |type, value| Member.cost(type, value) || (return nil) }
        end
      end
    end
  end
end
