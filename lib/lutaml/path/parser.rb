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
      rule(:glob_char) { match('[*?\[{]') }
      rule(:regular_char) do
        (separator.absent? >> str("\\").absent? >> any) |
          escaped_separator
      end

      # Single segment can contain any regular chars or glob chars
      rule(:segment_content) do
        (glob_char | regular_char).repeat(1).as(:content) >>
          glob_char.present?.maybe.as(:is_pattern)
      end

      rule(:segment) do
        segment_content.as(:segment)
      end

      rule(:segments) do
        (separator >> segment).repeat.as(:more_segments)
      end

      # Full path expression - either absolute or relative
      rule(:path_expr) do
        ((separator.as(:absolute) >> segment.as(:first_segment) >> segments) |
         (segment.as(:first_segment) >> segments))
      end

      root(:path_expr)
    end
  end
end
