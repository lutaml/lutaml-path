# frozen_string_literal: true

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

        # Re-escapes the dots the transformer unescaped, so a name containing
        # one round-trips: ["a.b"] must render as "a\\.b", not "a.b" (which
        # re-parses as the two names ["a", "b"]).
        def to_s = names.map { |n| n.gsub(".") { "\\." } }.join(".")
      end

      # A right-hand literal. `source` is the unescaped lexeme and is never
      # coerced: pattern? must read it directly so a numeric never reaches
      # String#match?.
      Value = Struct.new(:source, :type) do
        def initialize(*) = super.tap { source.freeze and freeze }

        def pattern?
          type == :string && source.match?(PathSegment::GLOB_CHARS)
        end

        # Re-escapes the quote the transformer unescaped, so a value containing
        # one round-trips: "O'Reilly" must render as 'O\'Reilly', not as
        # 'O'Reilly' (which fails to re-parse).
        def to_s
          type == :number ? source : "'#{source.gsub("'") { "\\'" }}'"
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

      Existence = Struct.new do
        def initialize(*) = super.tap { freeze }

        def to_s = "exists"
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
