# frozen_string_literal: true

require "parsanol"
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
require_relative "path/resolver"

module Lutaml
  module Path
    def self.parse(input)
      tree = Parser.new.parse(input)
      Transformer.new.apply(tree)
    rescue Parsanol::ParseFailed => e
      raise ParseError, e.message
    rescue SystemStackError
      # Transforming deeply nested conditions can also exhaust the stack.
      raise ParseError, "expression nests too deeply to parse"
    end

    # Resolves an instance data path against model instance data: a
    # lutaml-model Serializable instance, a hash, or collections
    # thereof. The path may be a parsed InstancePath or an instance
    # path string.
    def self.resolve(root, path)
      path = parse_instance(path) if path.is_a?(::String)
      Resolver.resolve(root, path)
    end

    # Parses an input explicitly as an instance data path.
    def self.parse_instance(input)
      tree = Parser.new.parse(input)
      Transformer.new.apply(tree)
    rescue Parslet::ParseFailed => e
      raise ParseError, e.message
    rescue SystemStackError
      raise ParseError, "expression nests too deeply to parse"
    end
  end
end
