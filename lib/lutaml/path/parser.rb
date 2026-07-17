# frozen_string_literal: true

# lib/lutaml/path/parser.rb
require "parslet"

module Lutaml
  module Path
    class Parser < Parslet::Parser
      rule(:space) { match('\s').repeat }

      rule(:escaped_separator) { str("\\") >> str("::") }
      rule(:separator) { str("::") }

      # Character rules
      rule(:regular_char) do
        (separator.absent? >> str("\\").absent? >> any) |
          escaped_separator
      end

      # Single segment can contain any regular chars
      rule(:segment_content) do
        regular_char.repeat(1).as(:content)
      end

      rule(:segment) do
        segment_content.as(:segment)
      end

      rule(:segments) do
        (separator >> segment).repeat.as(:more_segments)
      end

      # Full path expression - either absolute or relative
      rule(:path_expr) do
        (separator.as(:absolute) >> segment.as(:first_segment) >> segments) |
          (segment.as(:first_segment) >> segments)
      end

      # The leading separator cannot be escaped (README: "the leading hierarchy
      # separator ... cannot be escaped"). Guard position 0 of the input; a real
      # leading `::` is fine, so absolute paths and later-segment escapes are
      # unaffected.
      rule(:path) do
        escaped_separator.absent? >> path_expr
      end

      root(:path)
    end
  end
end
