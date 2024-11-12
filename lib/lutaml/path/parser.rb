# lib/lutaml/path/parser.rb
require "parslet"

module Lutaml
  module Path
    class Parser < Parslet::Parser
      rule(:space) { match('\s').repeat }

      rule(:escaped_separator) { str('\\') >> str("::") }
      rule(:separator) { str("::") }

      # Character rules
      rule(:glob_char) { match('[*?\[{]') }
      rule(:regular_char) {
        (separator.absent? >> str('\\').absent? >> any) |
        escaped_separator
      }

      # Single segment can contain any regular chars or glob chars
      rule(:segment_content) {
        ((glob_char | regular_char).repeat(1)).as(:content) >>
        (glob_char.present?).maybe.as(:is_pattern)
      }

      rule(:segment) {
        segment_content.as(:segment)
      }

      rule(:segments) {
        (separator >> segment).repeat.as(:more_segments)
      }

      # Full path expression - either absolute or relative
      rule(:path_expr) {
        ((separator.as(:absolute) >> segment.as(:first_segment) >> segments) |
         (segment.as(:first_segment) >> segments))
      }

      root(:path_expr)
    end
  end
end
