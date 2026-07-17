# frozen_string_literal: true

# lib/lutaml/path/transformer.rb
require "parslet"

module Lutaml
  module Path
    class Transformer < Parslet::Transform
      # --- condition AST ----------------------------------------------------
      # Split on UNESCAPED dots only, then unescape: "a\\.b" is one attribute
      # named "a.b", not the two names ["a\\", "b"].
      rule(attref: simple(:a)) do
        Condition::AttributeRef.new(a.to_s.split(/(?<!\\)\./).map { |n| n.gsub('\.', ".") })
      end
      # An empty quoted value ('') makes Parslet's repeat yield [] rather than a
      # slice, so `simple` would never match and the node would stay raw.
      rule(string: subtree(:s)) do
        Condition::Value.new(s.is_a?(Array) ? "" : s.to_s.gsub("\\'", "'"), :string)
      end
      rule(number: simple(:n)) { Condition::Value.new(n.to_s, :number) }
      rule(exists: simple(:_)) { Condition::Existence.new }

      rule(lhs: subtree(:l), op: simple(:o), rhs: subtree(:r)) do |d|
        Condition::Comparison.new(d[:l], d[:o].to_s, d[:r])
      end

      # Parslet collapses a one-element repetition to a bare Hash rather than a
      # one-element Array, and Array({v: x}) would yield [[:v, x]] via Hash#to_a
      # -- so `in ('ISBN')` used to raise TypeError out of Lutaml::Path.parse.
      # Wrap-then-flatten normalises both shapes.
      rule(lhs: subtree(:l), literals: subtree(:v)) do |d|
        Condition::Membership.new(d[:l], [d[:v]].flatten.map { |h| h[:v] })
      end

      rule(not: subtree(:n)) { Condition::Negation.new(n) }

      rule(binary: { left: subtree(:l), operator: simple(:o), right: subtree(:r) }) do |d|
        Condition::BinaryOperation.new(d[:o].to_s, d[:l], d[:r])
      end

      # --- steps ------------------------------------------------------------
      # Every segment becomes a Step uniformly. The transform builds bottom-up
      # and a leaf cannot know whether the whole path has dot-steps or filters,
      # so the root rule -- the only place that knows -- decides the type and
      # unwraps Step -> PathSegment when it picks ElementPath.
      rule(content: simple(:content)) do |dict|
        Step.new(PathSegment.new(dict[:content].to_s))
      end

      rule(content: simple(:content), condition: subtree(:cond)) do |dict|
        Step.new(PathSegment.new(dict[:content].to_s), condition: dict[:cond])
      end

      rule(segment: subtree(:segment)) { segment }

      # Single root rule. `abs` is nil for a relative path and a "::" slice for
      # an absolute one. One rule means one key set, so adding a key later
      # cannot silently un-match the root and hand back a raw Hash.
      rule(
        absolute: simple(:abs),
        first_segment: simple(:first),
        more_segments: sequence(:rest),
        attrs: sequence(:attrs)
      ) do |dict|
        base = [dict[:first]] + Array(dict[:rest]).compact
        attributes = Array(dict[:attrs]).compact
        absolute = !dict[:abs].nil?

        if attributes.empty? && base.none?(&:condition?)
          ElementPath.new(base.map(&:segment), absolute: absolute)
        else
          InstancePath.new(base_steps: base, attribute_steps: attributes,
                           absolute: absolute)
        end
      end
    end
  end
end
