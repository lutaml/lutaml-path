# frozen_string_literal: true

module Lutaml
  module Path
    class PathSegment
      GLOB_CHARS = /[*?\[{]/

      attr_reader :name, :source

      # Deliberately no `\[` unescape: a backslash before a glob character
      # must survive into fnmatch's own escaper, which is what makes a literal
      # "[" expressible. Unescaping it here would turn "Foo\[A-Z]" back into a
      # character set.
      def initialize(name)
        @source = name
        @name = name.gsub('\::', "::").gsub('\.', ".")
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

      # Renders the RAW source, so escapes survive a round-trip: "core\::t"
      # must render back as "core\::t", not as the unescaped "core::t".
      def to_s
        @source
      end

      def ==(other)
        other.instance_of?(self.class) && name == other.name
      end
      alias eql? ==

      def hash
        [self.class, name].hash
      end
    end
  end
end
