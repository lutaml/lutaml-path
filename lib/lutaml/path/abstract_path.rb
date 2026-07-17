# frozen_string_literal: true

module Lutaml
  module Path
    # Common supertype for parsed paths. Holds only whether the path is
    # absolute.
    #
    # It deliberately declares neither match? nor segments: InstancePath
    # cannot honour match? under parse-only, and the two subclasses hold
    # genuinely different element types (PathSegment answers match?; Step,
    # which can carry a filter, must not).
    class AbstractPath
      attr_reader :absolute

      def initialize(absolute: false)
        @absolute = absolute
      end

      def absolute?
        @absolute
      end
    end
  end
end
