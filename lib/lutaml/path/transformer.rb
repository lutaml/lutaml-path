# frozen_string_literal: true

# lib/lutaml/path/transformer.rb
require "parslet"

module Lutaml
  module Path
    class Transformer < Parslet::Transform
      rule(content: simple(:content), is_pattern: simple(:is_pattern)) do |dict|
        content = dict[:content].to_s
        is_pattern = !dict[:is_pattern].nil?
        PathSegment.new(content, is_pattern: is_pattern)
      end

      rule(segment: subtree(:segment)) { segment }

      # Transform more_segments rule
      rule(more_segments: sequence(:segments)) { segments }
      rule(more_segments: simple(:segment)) { [segment].compact } # For single segment
      rule(more_segments: []) { [] } # For empty segments

      # Absolute path
      rule(
        absolute: simple(:_),
        first_segment: simple(:first),
        more_segments: sequence(:rest)
      ) do |dict|
        segments = [dict[:first]] + Array(dict[:rest]).compact
        ElementPath.new(segments, absolute: true)
      end

      # Relative path
      rule(
        first_segment: simple(:first),
        more_segments: sequence(:rest)
      ) do |dict|
        segments = [dict[:first]] + Array(dict[:rest]).compact
        ElementPath.new(segments, absolute: false)
      end
    end
  end
end
