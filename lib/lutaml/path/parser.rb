# frozen_string_literal: true

# lib/lutaml/path/parser.rb
require "parslet"

module Lutaml
  module Path
    class Parser < Parslet::Parser
      rule(:sp) { match('\s').repeat }
      rule(:sp?) { sp.maybe }

      rule(:escaped_separator) { str("\\") >> str("::") }
      rule(:escaped_dot) { str("\\") >> str(".") }
      rule(:separator) { str("::") }
      rule(:dot) { str(".") }

      # Character rules. A "." now terminates a segment, so it is excluded
      # here; "\." escapes it, mirroring how "\::" escapes the separator.
      rule(:regular_char) do
        (separator.absent? >> dot.absent? >> str("\\").absent? >> any) |
          escaped_separator | escaped_dot
      end

      # --- filter conditions ------------------------------------------------
      # Single quotes only: every value in the README is single-quoted. "\'"
      # escapes a quote and "\\" escapes a backslash -- both are needed, or a
      # value ending in a backslash renders as 'abc\' and its trailing escape
      # eats the closing quote. Any OTHER backslash is left intact so a future
      # evaluator's fnmatch still receives "\*" as a literal asterisk.
      rule(:quoted_string) do
        str("'") >> (
          (str("\\") >> (str("'") | str("\\"))) | (str("'").absent? >> any)
        ).repeat.as(:string) >> str("'")
      end

      rule(:number) { match("[0-9]").repeat(1).as(:number) }
      rule(:literal) { quoted_string | number }

      rule(:ident_char) { match('[^\s\[\]().,=!<>&|\']') }
      rule(:attribute_ref) do
        (ident_char.repeat(1) >> (dot >> ident_char.repeat(1)).repeat).as(:attref)
      end

      # Maximal munch: "!=" before "!", ">=" before ">".
      #
      # Defined once and shared with sniff_op. The sniff exists so a typo'd
      # filter fails loudly rather than degrading to a character set; an
      # operator added here but forgotten there would produce exactly the
      # silent degradation the sniff was built to prevent.
      rule(:cmp_lexeme) do
        str("!=") | str(">=") | str("<=") | str("=") | str("<") | str(">")
      end

      rule(:cmp_op) { cmp_lexeme.as(:op) }

      # Like `and`, `exists` needs a token boundary: without it
      # "existsand b='2'" silently parses as `(exists and b='2')`.
      # `in` needs none — membership must proceed to "(" to match at all.
      rule(:existence) { str("exists").as(:exists) >> ident_char.absent? }

      rule(:membership) do
        attribute_ref.as(:lhs) >> sp >> str("in") >> sp? >>
          str("(") >> sp? >>
          (literal.as(:v) >> (sp? >> str(",") >> sp? >> literal.as(:v)).repeat).as(:literals) >>
          sp? >> str(")")
      end

      rule(:comparison) do
        attribute_ref.as(:lhs) >> sp? >> cmp_op >> sp? >> literal.as(:rhs)
      end

      # Most specific first, bare keyword last. If `existence` led, "exists"
      # would be consumed as the keyword and an attribute actually named
      # "exists" could never be compared -- while "in" and "and" could, which
      # is a silent asymmetry. Ordering this way, "[exists]" still resolves:
      # comparison finds no operator, membership finds no "in", existence wins.
      rule(:predicate) { membership | comparison | existence }

      # Boolean layering encodes precedence: ! tightest, then comparison,
      # then &&, then ||. or_expr must sit ABOVE and_expr so || becomes the
      # root of "a || b && c". README never states precedence; this is the
      # conventional order and is documented in the README by this PR.
      rule(:group) { str("(") >> sp? >> or_expr >> sp? >> str(")") }
      rule(:primary) { group | predicate }
      rule(:not_expr) { (str("!") >> sp? >> not_expr).as(:not) | primary }

      # `and` needs the same token boundary the sniff uses, or "android='2'"
      # silently parses as `and` + the attribute "roid" rather than raising.
      rule(:and_op) { str("&&") | (str("and") >> ident_char.absent?) }

      rule(:and_expr) do
        (not_expr.as(:left) >> sp? >> and_op.as(:operator) >>
          sp? >> and_expr.as(:right)).as(:binary) | not_expr
      end

      rule(:or_expr) do
        (and_expr.as(:left) >> sp? >> str("||").as(:operator) >>
          sp? >> or_expr.as(:right)).as(:binary) | and_expr
      end

      rule(:condition) { or_expr }

      # --- the bracket rule (operator-sniff) --------------------------------
      # "[" opens a FILTER iff (1) it is at offset > 0 in its segment,
      # (2) its matching "]" -- found quote-aware -- terminates the segment,
      # and (3) its body contains a condition operator. Otherwise "[" is an
      # ordinary glob character set belonging to the name.
      rule(:seg_end) { separator | dot | any.absent? }

      # The sniff is TOKEN-aware: it tokenises with ident_char, the same
      # alphabet attribute_ref uses, so an identifier is one token wherever it
      # appears and a word operator only counts when no ident_char follows it.
      # Otherwise ordinary character sets are wrongly claimed as filters and
      # rejected -- "[print]" and "[min]" would match on their inner "in",
      # "[standard]" on "and", "[coexists]" on "exists".
      rule(:sniff_word) { ident_char.repeat(1) }
      rule(:sniff_atom) { quoted_string | sniff_word | (str("]").absent? >> any) }
      # Comparisons and the and-family reuse the grammar's own rules, so they
      # cannot drift out of sync. "||" is one fixed token. "in" and "exists"
      # stay spelled out: the grammar bounds "in" by the "(" that must follow
      # it rather than by a character lookahead, and `existence` captures the
      # word it matches, so neither reads back cleanly as a bare matcher.
      rule(:sniff_op) do
        cmp_lexeme | and_op | str("||") |
          ((str("in") | str("exists")) >> ident_char.absent?)
      end

      rule(:filter_ahead) do
        str("[") >>
          (str("]").absent? >> sniff_op.absent? >> sniff_atom).repeat >>
          sniff_op >> sniff_atom.repeat >>
          str("]") >> seg_end.present?
      end

      # Once the sniff fires the filter MUST parse: no fallback, so a typo'd
      # filter fails loudly instead of silently becoming a character set.
      rule(:filter) do
        filter_ahead.present? >>
          str("[") >> sp? >> condition.as(:condition) >> sp? >> str("]")
      end

      # A bracket group the sniff has not claimed is consumed WHOLE, so a "."
      # or "::" inside a character set is literal rather than a separator:
      # "Class[.]" and "Class[a.b]" stay single-segment charsets. regular_char
      # still accepts "[" so an unbalanced "x[" remains a name.
      rule(:charset_group) { str("[") >> (str("]").absent? >> any).repeat >> str("]") }
      rule(:name_atom) { charset_group | regular_char }

      # The first character ALWAYS belongs to the name -- clause 1 ("a [ at
      # offset 0 is always a charset") encoded literally. Only later positions
      # may stop at a filter. Both halves are load-bearing: without the
      # filter_ahead.absent? guard the name swallows the whole filter and every
      # filter parses as a charset; without the leading unconditional name_atom
      # filter_ahead fires at offset 0 too and "pkg::[exists]" raises.
      rule(:segment_content) do
        (name_atom >> (filter_ahead.absent? >> name_atom).repeat).as(:content)
      end

      rule(:segment) do
        (segment_content >> filter.maybe).as(:segment)
      end

      rule(:segments) do
        (separator >> segment).repeat.as(:more_segments)
      end

      # The attribute part. "::" never follows "." (verified: zero README
      # examples), so the namespace part is consumed first, then this.
      rule(:attributes) do
        (dot >> segment).repeat.as(:attrs)
      end

      # Full path expression. `absolute` is ALWAYS emitted (nil when relative)
      # so the transform sees one stable key set: Parslet matches a hash on its
      # exact keys, and a second root rule would have to be duplicated for
      # every key added later.
      rule(:path_expr) do
        separator.maybe.as(:absolute) >>
          segment.as(:first_segment) >>
          segments >>
          attributes
      end

      # Neither leading separator may be escaped. README:212-218 forbids BOTH
      # "\::Rectangle::Shape" and "\.width.length". Guard position 0 of the
      # input; a real leading "::" is fine, so absolute paths and
      # later-segment escapes are unaffected.
      rule(:path) do
        escaped_separator.absent? >> escaped_dot.absent? >> path_expr
      end

      root(:path)
    end
  end
end
