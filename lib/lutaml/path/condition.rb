# frozen_string_literal: true

require_relative "path_segment"

module Lutaml
  module Path
    # The filter-condition AST.
    #
    # Parse-only: these nodes carry structure and render themselves, and
    # evaluate nothing. They are Structs because there is no behaviour to
    # justify hand-written classes, and Struct supplies value equality for
    # free. Data.define would also freeze them, but it is Ruby 3.2+ and this
    # gem supports 3.0.
    #
    # Every node freezes itself, along with any collection or string it owns:
    # a parsed AST must be immutable, and Struct otherwise hands out public
    # setters. Freezing the Struct alone is shallow -- `names << "x"` would
    # still mutate, and would silently invalidate the Struct's own hash.
    module Condition
      # A dotted left-hand side: "role.type" -> ["role", "type"].
      AttributeRef = Struct.new(:names) do
        def initialize(*) = super.tap { names.each(&:freeze).freeze and freeze }

        # Re-escapes BOTH the dot and the backslash the transformer unescaped.
        # Escaping only the dot is incomplete: a name ending in a backslash
        # would render as "a\.b" and re-parse as the single name "a.b".
        def to_s
          names.map { |n| n.gsub(/([\\.])/) { "\\#{::Regexp.last_match(1)}" } }.join(".")
        end
      end

      # A right-hand literal. `source` is the unescaped lexeme and is never
      # coerced: pattern? must read it directly so a numeric never reaches
      # String#match?.
      Value = Struct.new(:source, :type) do
        def initialize(*) = super.tap { source.freeze and freeze }

        def pattern?
          type == :string && source.match?(PathSegment::GLOB_CHARS)
        end

        # Re-escapes BOTH the quote and the backslash the transformer
        # unescaped. Escaping only the quote is incomplete: a value ending in a
        # backslash would render as 'abc\' and its trailing escape would eat
        # the closing quote.
        def to_s
          return source if type == :number

          "'#{source.gsub(/(['\\])/) { "\\#{::Regexp.last_match(1)}" }}'"
        end
      end

      Comparison = Struct.new(:lhs, :op, :rhs) do
        def initialize(*) = super.tap { op.freeze and freeze }

        def to_s = "#{lhs}#{op}#{rhs}"
      end

      # `literals`, not `values`: a member named `values` would shadow
      # Struct#values, which returns the member list.
      Membership = Struct.new(:lhs, :literals) do
        def initialize(*) = super.tap { literals.freeze and freeze }

        def to_s = "#{lhs} in (#{literals.join(",")})"
      end

      # `exists` carries no operand, so there is no member to declare. Written
      # as a plain class rather than a zero-member Struct, which Ruby permits
      # only from 3.3 while this gem supports >= 3.0.
      class Existence
        def initialize = freeze

        def to_s = "exists"

        # instance_of?, not is_a?: exact-class equality is what the Struct gave,
        # and hash is keyed on the class, so is_a? would make a subclass compare
        # asymmetrically against a differing hash.
        def ==(other) = other.instance_of?(self.class)
        alias eql? ==

        def hash = self.class.hash
      end

      # && and || are structurally identical, so one type carries both.
      # to_s ALWAYS parenthesises: parse(p.to_s) == p asserts TREE equality,
      # and explicit parens make re-association impossible on a re-parse.
      BinaryOperation = Struct.new(:operator, :left, :right) do
        def initialize(*) = super.tap { operator.freeze and freeze }

        def to_s = "(#{left} #{operator} #{right})"
      end

      Negation = Struct.new(:operand) do
        def initialize(*) = super.tap { freeze }

        def to_s = "!#{operand}"
      end
    end
  end
end
