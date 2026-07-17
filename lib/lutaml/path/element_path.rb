# frozen_string_literal: true

require_relative "abstract_path"

module Lutaml
  module Path
    class ElementPath < AbstractPath
      attr_reader :segments

      def initialize(segments, absolute: false)
        super(absolute: absolute)
        @segments = Array(segments)
      end

      def to_s
        "#{absolute? ? "::" : ""}#{segments.join("::")}"
      end

      def ==(other)
        other.is_a?(self.class) &&
          absolute? == other.absolute? &&
          segments == other.segments
      end
      alias eql? ==

      def hash
        [self.class, absolute?, segments].hash
      end

      def match?(path_segments)
        reachable = terminal_row(path_segments.length)

        segments.reverse_each do |segment|
          reachable = advance(segment, path_segments, reachable)
        end

        reachable[0]
      end

      private

      # Row for a fully-consumed pattern: an absolute pattern must have consumed
      # the whole candidate; a relative pattern matches a prefix, so any trailing
      # candidate segments are allowed.
      def terminal_row(path_length)
        Array.new(path_length + 1) do |path_index|
          absolute? ? path_index == path_length : true
        end
      end

      # Fold one pattern segment (walking right to left) into the reachability
      # row. reachable[i] answers "can the rest of the pattern match path[i..]?".
      def advance(segment, path_segments, reachable)
        if segment.deep_wildcard?
          deep_wildcard_row(path_segments.length, reachable)
        else
          segment_row(segment, path_segments, reachable)
        end
      end

      # A `**` reaches i by consuming zero (the rest of the pattern reaches i) or
      # one more segment (the same `**` reaches i + 1).
      def deep_wildcard_row(path_length, reachable)
        row = Array.new(path_length + 1)
        row[path_length] = reachable[path_length]
        (path_length - 1).downto(0) { |i| row[i] = reachable[i] || row[i + 1] }
        row
      end

      # A normal segment reaches i only by matching path[i] and having the rest
      # of the pattern reach i + 1.
      def segment_row(segment, path_segments, reachable)
        path_length = path_segments.length
        row = Array.new(path_length + 1)
        row[path_length] = false
        (path_length - 1).downto(0) do |i|
          row[i] = segment.match?(path_segments[i]) && reachable[i + 1]
        end
        row
      end
    end
  end
end
