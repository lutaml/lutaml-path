# frozen_string_literal: true

module Lutaml
  module Path
    class PathSegment
      GLOB_CHARS = /[*?\[{]/

      attr_reader :name

      def initialize(name)
        @name = name.gsub('\::', "::")
        @pattern = @name.match?(GLOB_CHARS)
      end

      def pattern?
        @pattern
      end

      def deep_wildcard?
        name == "**"
      end

      def match?(segment)
        return File.fnmatch(name, segment, File::FNM_EXTGLOB) if pattern?

        name == segment
      end
    end
  end
end
