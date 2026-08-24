# frozen_string_literal: true

module Lutaml
  module Path
    class ParseError < StandardError; end

    # Raised when a path parses but the operation asked of it is not
    # implemented. A StandardError, unlike Ruby's NotImplementedError, which
    # descends from ScriptError and so escapes `rescue => e`.
    class ResolutionError < StandardError; end
  end
end
