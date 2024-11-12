# frozen_string_literal: true

module Lutaml
  module Path
    class ElementPath
      attr_reader :segments, :absolute

      def initialize(segments, absolute: false)
        @segments = Array(segments)
        @absolute = absolute
      end

      def absolute?
        @absolute
      end

      def match?(path_segments)
        return false if absolute? && path_segments.length != segments.length
        return false if path_segments.length < segments.length

        segments.zip(path_segments).all? { |seg, path_seg| seg.match?(path_seg) }
      end
    end
  end
end
