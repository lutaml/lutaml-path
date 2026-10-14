# frozen_string_literal: true

module Lutaml
  module Path
    # Evaluates Condition AST nodes against a context object. The
    # condition classes are parse-only by design; this module is the
    # evaluation half, wired to the same name-resolution the instance
    # traversal uses.
    module ConditionEvaluator
      module_function

      def evaluate(condition, object)
        case condition
        when Condition::Comparison then compare(condition, object)
        when Condition::Membership then membership(condition, object)
        when Condition::Existence then true
        when Condition::Negation then !evaluate(condition.operand, object)
        when Condition::BinaryOperation then evaluate_binary(condition, object)
        end
      end

      def evaluate_binary(condition, object)
        left = evaluate(condition.left, object)
        right = evaluate(condition.right, object)
        condition.operator == "&&" ? left && right : left || right
      end

      def compare(condition, object)
        actual = read_path(object, condition.lhs)
        expected = condition.rhs
        case condition.op
        when "=" then values_equal(actual, expected)
        when "!=" then !values_equal(actual, expected)
        else ordered(actual, condition.op, expected)
        end
      end

      def membership(condition, object)
        actual = read_path(object, condition.lhs)
        condition.literals.any? { |literal| values_equal(actual, literal) }
      end

      def values_equal(actual, value)
        return false if actual.nil?

        value.pattern? ? value_match?(value, actual) : values_coerced_equal(actual, value)
      end

      def value_match?(value, actual)
        File.fnmatch(value.source, actual.to_s, File::FNM_EXTGLOB)
      end

      def values_coerced_equal(actual, value)
        pair = numeric_pair(actual, value)
        pair ? pair[0] == pair[1] : actual.to_s == value.source
      end

      def ordered(actual, operator, value)
        return false if actual.nil?

        pair = numeric_pair(actual, value)
        if pair
          actual = pair[0]
          value = pair[1]
        end
        actual.to_s.public_send(ruby_operator(operator), value.to_s)
      end

      def ruby_operator(operator)
        { "=" => :==, "!=" => :"!=", ">=" => :>=, "<=" => :<=, ">" => :>, "<" => :< }.fetch(operator)
      end

      def numeric_pair(actual, value)
        numeric(actual) && numeric(value) ? [numeric(actual), numeric(value)] : nil
      end

      # Accepts both AST literals (Value structs) and raw data values.
      def numeric(value)
        raw = value.respond_to?(:source) ? value.source : value
        Float(raw)
      rescue ::ArgumentError, ::TypeError
        nil
      end

      def read_path(object, attribute_ref)
        context = [object]
        attribute_ref.names.each do |name|
          context = context.flat_map { |node| exact_children(node, name) }
        end
        return nil if context.empty?

        context.first
      end

      def exact_children(node, name)
        entries(node).filter_map do |child_name, value|
          next if value.nil?
          next unless child_name.to_s == name

          value.is_a?(::Enumerable) && !value.is_a?(::Hash) && !value.is_a?(::String) ? value.to_a : value
        end.flatten(1)
      end

      def entries(node)
        Resolver.entries(node)
      end
    end
  end
end
