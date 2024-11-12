# frozen_string_literal: true

module Lutaml
  module Path
    class PathSegment
      attr_reader :name, :pattern

      def initialize(name, is_pattern: false)
        @name = name.gsub('\::', "::")
        @pattern = is_pattern
      end

      def pattern?
        @pattern
      end

      def match?(segment)
        return File.fnmatch(name, segment) if pattern?

        name == segment
      end
    end
  end
end
