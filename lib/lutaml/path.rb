# frozen_string_literal: true

require "parslet"
require_relative "path/version"
require_relative "path/parser"
require_relative "path/transformer"
require_relative "path/element_path"
require_relative "path/path_segment"

module Lutaml
  module Path
    class ParseError < StandardError; end

    def self.parse(input)
      tree = Parser.new.parse(input)
      Transformer.new.apply(tree)
    rescue Parslet::ParseFailed => e
      raise ParseError, e.message
    end
  end
end
