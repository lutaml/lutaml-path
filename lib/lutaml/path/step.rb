# frozen_string_literal: true

require "forwardable"

module Lutaml
  module Path
    # One segment of a path plus the filter condition attached to it.
    #
    # Step composes a PathSegment rather than extending it, and deliberately
    # does NOT answer match?: a step can carry a condition, and matching by
    # name alone would silently ignore that condition and report a match for
    # a path that says something narrower. PathSegment stays filter-free and
    # keeps match?; anything that can carry a filter never answers it.
    #
    # Composition is also required for correctness: "**[name='ISO']" as a
    # single PathSegment name is not a deep wildcard, whereas name "**" plus a
    # separate condition keeps deep_wildcard? true.
    class Step
      extend Forwardable

      attr_reader :segment, :condition

      def_delegators :segment, :name, :pattern?, :deep_wildcard?

      def initialize(segment, condition: nil)
        @segment = segment
        @condition = condition
      end

      def condition?
        !condition.nil?
      end

      def to_s
        condition? ? "#{segment}[#{condition}]" : segment.to_s
      end

      def ==(other)
        other.instance_of?(self.class) &&
          segment == other.segment &&
          condition == other.condition
      end
      alias eql? ==

      def hash
        [self.class, segment, condition].hash
      end
    end
  end
end
