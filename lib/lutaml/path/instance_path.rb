# frozen_string_literal: true

require_relative "abstract_path"

module Lutaml
  module Path
    # A parsed instance-data path: a base (the "::" anchor) plus dot-separated
    # attribute navigation, with optional filter conditions on any step.
    #
    # Parse-only. It carries structure and renders itself; resolving it against
    # real model data is out of scope, so match? raises rather than lying by
    # matching on names and silently ignoring the conditions.
    class InstancePath < AbstractPath
      attr_reader :base_steps, :attribute_steps

      def initialize(base_steps:, attribute_steps: [], absolute: false)
        super(absolute: absolute)
        @base_steps = Array(base_steps)
        @attribute_steps = Array(attribute_steps)
      end

      def steps
        base_steps + attribute_steps
      end

      def conditions
        steps.filter_map(&:condition)
      end

      def match?(_path_segments)
        raise NotImplementedError,
              "instance paths are parsed but not resolved: #{self}. " \
              "If you meant a literal dot in an element name, escape it: a\\.b"
      end

      def to_s
        "#{absolute? ? "::" : ""}#{base_steps.join("::")}" \
          "#{attribute_steps.map { |s| ".#{s}" }.join}"
      end

      def ==(other)
        other.is_a?(self.class) &&
          absolute? == other.absolute? &&
          base_steps == other.base_steps &&
          attribute_steps == other.attribute_steps
      end
      alias eql? ==

      def hash
        [self.class, absolute?, base_steps, attribute_steps].hash
      end
    end
  end
end
