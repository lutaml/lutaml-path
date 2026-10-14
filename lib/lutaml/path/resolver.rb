# frozen_string_literal: true

require_relative "condition"
require_relative "condition_evaluator"
require_relative "step"
require_relative "instance_path"

module Lutaml
  module Path
    # Resolves parsed instance paths against real model data:
    # lutaml-model Serializable instances, plain hashes, and their
    # collections. This is the evaluation half of RS 3002's instance
    # data syntax — the parser deliberately stays parse-only
    # (InstancePath#match? raises), so resolution lives here where the
    # object-model knowledge (attributes, hashes, enumerables)
    # belongs.
    #
    # Resolution walks InstancePath#steps: base steps anchor the root
    # (treated as attribute navigation from the given root), attribute
    # steps read named children, `**` selects every descendant, and a
    # step's condition filters the step's candidate nodes.
    module Resolver
      module_function

      def resolve(root, path)
        path = normalized(path)
        context = [root]
        path.steps.each do |step|
          context = apply_step(context, step)
        end
        finalize(context, path)
      end

      def apply_step(context, step)
        context = if step.deep_wildcard?
                    descendants(context)
                  else
                    context.flat_map { |node| named_children(node, step) }
                  end
        step.condition? ? filter(context, step.condition) : context
      end

      def filter(context, condition)
        context.select { |node| ConditionEvaluator.evaluate(condition, node) }
      end

      # Reads a dotted AttributeRef ("role.type") from a context node.
      # Condition paths are plain names (the grammar admits no glob
      # characters in attribute references).
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

      def named_children(node, step)
        named_targets(node, step.segment)
      end

      # Children of `node` whose name matches the step's segment; a
      # collection value contributes its elements.
      def named_targets(node, segment)
        entries(node).filter_map do |child_name, value|
          next if value.nil?
          next unless segment.match?(child_name.to_s)

          value.is_a?(::Enumerable) && !value.is_a?(::Hash) && !value.is_a?(::String) ? value.to_a : value
        end.flatten(1)
      end

      def descendants(context)
        seen = {}.compare_by_identity
        context.each do |node|
          walk(node) { |value| seen[value] = true unless value.nil? }
        end
        seen.keys
      end

      def walk(node, &block)
        entries(node).map(&:last).each do |value|
          next if value.nil?

          block.call(value)
          walk(value, &block)
        end
      end

      # (name, value) pairs addressable on `node`.
      def entries(node)
        return [] if primitive?(node)

        if node.is_a?(::Hash)
          node.map { |key, value| [key, value] }
        elsif node.is_a?(::Enumerable)
          node.each_with_index.map { |value, index| [index, value] }
        elsif model_instance?(node)
          model_entries(node)
        else
          []
        end
      end

      def primitive?(node)
        node.nil? || node.is_a?(::String) || node.is_a?(::Numeric) || node.is_a?(::Symbol)
      end

      def model_instance?(node)
        defined?(Lutaml::Model) && node.is_a?(Lutaml::Model::Serializable)
      end

      def model_entries(node)
        node.class.attributes.keys.filter_map do |name|
          next unless node.respond_to?(name)

          [name, node.public_send(name)]
        end
      end

      # A bare name parses as a model path (the grammar's default);
      # for resolution its segments are attribute steps.
      def normalized(path)
        return path if path.respond_to?(:steps)

        steps = path.segments.map { |segment| Step.new(segment) }
        InstancePath.new(base_steps: [], attribute_steps: steps, absolute: path.absolute?)
      end

      # Plain chains (no filters, patterns, or deep wildcards) resolve
      # to a single value when exactly one non-collection node matched;
      # everything else returns the collection.
      def finalize(context, path)
        plain = path.steps.none? do |step|
          step.condition? || step.pattern? || step.deep_wildcard?
        end
        return context.first if plain && context.size == 1 && !context.first.is_a?(::Enumerable)

        context
      end
    end
  end
end
