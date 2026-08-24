# frozen_string_literal: true

require "parslet"
require_relative "path/version"
require_relative "path/errors"
require_relative "path/parser"
require_relative "path/transformer"
require_relative "path/path_segment"
require_relative "path/condition"
require_relative "path/step"
# abstract_path must precede element_path: `class ElementPath < AbstractPath`
# resolves the constant at class-definition time.
require_relative "path/abstract_path"
require_relative "path/element_path"
require_relative "path/instance_path"

module Lutaml
  module Path
    def self.parse(input)
      tree = Parser.new.parse(input)
      Transformer.new.apply(tree)
    rescue Parslet::ParseFailed => e
      raise ParseError, e.message
    rescue SystemStackError
      # The condition grammar recurses through group/not/and/or, so an input
      # nested deeply enough (~200 parentheses) exhausts the stack. That is a
      # property of the input, not a bug in the caller: parse must only ever
      # raise ParseError.
      raise ParseError, "expression nests too deeply to parse"
    end
  end
end
