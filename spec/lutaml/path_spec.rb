# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Path do
  describe ".parse" do
    it "parses simple paths" do
      path = described_class.parse("Element")
      expect(path.absolute?).to be false
      expect(path.segments.length).to eq(1)
      expect(path.segments.first.name).to eq("Element")
      expect(path.segments.first.pattern?).to be false
    end

    it "parses absolute paths" do
      path = described_class.parse("::Package::Element")
      expect(path.absolute?).to be true
      expect(path.segments.map(&:name)).to eq(%w[Package Element])
    end

    it "returns an ElementPath, never a raw parse tree" do
      expect(described_class.parse("Package::Class")).to be_a(Lutaml::Path::ElementPath)
      expect(described_class.parse("::Package::Class")).to be_a(Lutaml::Path::ElementPath)
    end

    it "parses paths with patterns" do
      path = described_class.parse("Package::*::Base*")
      expect(path.segments.map(&:pattern?)).to eq([false, true, true])
      expect(path.segments.map(&:name)).to eq(["Package", "*", "Base*"])
    end

    it "handles escaped separators" do
      path = described_class.parse("core\\::types::Element")
      expect(path.segments.map(&:name)).to eq(["core::types", "Element"])
    end

    it "does not treat escaped separators as patterns" do
      path = described_class.parse("core\\::types::Element")
      expect(path.segments.map(&:pattern?)).to eq([false, false])
    end

    it "rejects a leading escaped separator" do
      expect { described_class.parse("\\::Rectangle") }.to raise_error(described_class::ParseError)
      expect { described_class.parse("\\::Rectangle::Shape") }.to raise_error(described_class::ParseError)
    end

    it "allows an escaped separator in a later segment" do
      path = described_class.parse("model::\\::odd")
      expect(path.segments.map(&:name)).to eq(["model", "::odd"])
    end

    it "allows an escaped separator after a real leading separator" do
      path = described_class.parse("::\\::odd")
      expect(path.absolute?).to be true
      expect(path.segments.map(&:name)).to eq(["::odd"])
    end

    it "handles Unicode characters" do
      path = described_class.parse("建物::窓::ガラス")
      expect(path.segments.map(&:name)).to eq(%w[建物 窓 ガラス])
    end

    it "handles glob patterns" do
      path = described_class.parse("pkg::{a,b}*::[0-9]*")
      expect(path.segments.last.pattern?).to be true
      expect(path.match?(%w[pkg btest 123])).to be true
    end

    it "matches a single-segment wildcard end to end" do
      path = described_class.parse("Package::*::BaseClass")
      expect(path.match?(%w[Package core BaseClass])).to be true
      expect(path.match?(%w[Package BaseClass])).to be false
    end

    it "matches brace alternation end to end" do
      path = described_class.parse("model::{Abstract,Base}Class")
      expect(path.match?(%w[model AbstractClass])).to be true
      expect(path.match?(%w[model BaseClass])).to be true
      expect(path.match?(%w[model OtherClass])).to be false
    end

    it "matches a deep wildcard at any depth" do
      path = described_class.parse("Pkg::**::Element")
      expect(path.match?(%w[Pkg Element])).to be true
      expect(path.match?(%w[Pkg a Element])).to be true
      expect(path.match?(%w[Pkg a b Element])).to be true
      expect(path.match?(%w[Other a Element])).to be false
      expect(path.match?(%w[Pkg a b Other])).to be false
    end

    it "matches multiple deep wildcards" do
      path = described_class.parse("Pkg::**::mid::**::End")
      expect(path.match?(%w[Pkg a mid b End])).to be true
      expect(path.match?(%w[Pkg mid End])).to be true
      expect(path.match?(%w[Pkg mid Other])).to be false
    end

    it "matches a leading deep wildcard" do
      path = described_class.parse("**::Element")
      expect(path.match?(%w[Element])).to be true
      expect(path.match?(%w[a b Element])).to be true
      expect(path.match?(%w[a b Other])).to be false
    end

    it "matches a trailing deep wildcard" do
      path = described_class.parse("Pkg::**")
      expect(path.match?(%w[Pkg])).to be true
      expect(path.match?(%w[Pkg a b])).to be true
      expect(path.match?(%w[Other])).to be false
    end

    it "matches a bare deep wildcard against any depth" do
      path = described_class.parse("**")
      expect(path.match?([])).to be true
      expect(path.match?(%w[a])).to be true
      expect(path.match?(%w[a b c])).to be true
    end

    it "collapses adjacent deep wildcards" do
      path = described_class.parse("Pkg::**::**::End")
      expect(path.match?(%w[Pkg End])).to be true
      expect(path.match?(%w[Pkg a b End])).to be true
      expect(path.match?(%w[Pkg a b])).to be false
      expect(path.match?(%w[Other End])).to be false
    end

    it "requires an absolute deep-wildcard path to consume the whole candidate" do
      path = described_class.parse("::Pkg::**::End")
      expect(path.match?(%w[Pkg End])).to be true
      expect(path.match?(%w[Pkg a End])).to be true
      expect(path.match?(%w[Pkg a End extra])).to be false
    end

    it "matches a relative deep-wildcard path as a prefix" do
      path = described_class.parse("Pkg::**::Element")
      expect(path.match?(%w[Pkg a Element extra])).to be true
    end

    it "treats a double-asterisk substring as a glob, not a deep wildcard" do
      path = described_class.parse("pkg::a**b::x")
      expect(path.segments.map(&:deep_wildcard?)).to eq([false, false, false])
      expect(path.match?(%w[pkg aQQb x])).to be true
      expect(path.match?(%w[pkg aQQb extra x])).to be false
    end

    it "parses dot navigation" do
      path = described_class.parse("obj.edition.number")
      expect(path).to be_a(Lutaml::Path::InstancePath)
      expect(path.base_steps.map(&:name)).to eq(%w[obj])
      expect(path.attribute_steps.map(&:name)).to eq(%w[edition number])
    end

    it "parses a mixed :: and . path" do
      path = described_class.parse("::Shapes::Rectangle.width")
      expect(path).to be_a(Lutaml::Path::InstancePath)
      expect(path.absolute?).to be true
      expect(path.base_steps.map(&:name)).to eq(%w[Shapes Rectangle])
      expect(path.attribute_steps.map(&:name)).to eq(%w[width])
    end

    it "unescapes an escaped dot inside an attribute name" do
      path = described_class.parse("::Rectangle.width\\.length")
      expect(path.attribute_steps.map(&:name)).to eq(["width.length"])
    end

    it "rejects a leading escaped dot" do
      expect { described_class.parse("\\.width.length") }
        .to raise_error(described_class::ParseError)
    end

    it "keeps a dotless path an ElementPath" do
      expect(described_class.parse("model::shapes::Rectangle::area"))
        .to be_a(Lutaml::Path::ElementPath)
    end

    it "treats a bracket at offset 0 as a charset, even with an operator body" do
      # Clause 1. These are NOT in the accepted break set (which is offset > 0
      # only). A naive filter_ahead guard breaks these.
      expect(described_class.parse("pkg::[A-Z]*").segments.last.pattern?).to be true
      expect(described_class.parse("pkg::[exists]").segments.last.name).to eq("[exists]")
      expect(described_class.parse("pkg::[a=b]").segments.last.name).to eq("[a=b]")
      expect(described_class.parse("pkg::[!CV]ase").segments.last.name).to eq("[!CV]ase")
    end

    it "classifies brackets as charset or filter" do
      expect(described_class.parse("pkg::Class[A-Z]").segments.last.name).to eq("Class[A-Z]")
      expect(described_class.parse("pkg::Base*[0-9]").segments.last.name).to eq("Base*[0-9]")
      expect(described_class.parse("pkg::a[b-c]d").segments.last.name).to eq("a[b-c]d")
      expect(described_class.parse("pkg::x[!foo]").segments.last.name).to eq("x[!foo]")
      expect(described_class.parse("contributor[exists]")).to be_a(Lutaml::Path::InstancePath)
    end

    it "parses every filter form the README documents" do
      c = Lutaml::Path::Condition
      cmp = described_class.parse("obj.contributor[role.type='publisher']")
      expect(cmp.attribute_steps.last.condition)
        .to eq(c::Comparison.new(c::AttributeRef.new(%w[role type]), "=",
                                 c::Value.new("publisher", :string)))

      expect(described_class.parse("obj.docidentifier[type!='ISBN']")
        .attribute_steps.last.condition.op).to eq("!=")

      expect(described_class.parse("obj.docidentifier[type in ('ISBN','ISSN','DOI')]")
        .attribute_steps.last.condition.literals.map(&:source)).to eq(%w[ISBN ISSN DOI])

      expect(described_class.parse("obj.contributor[exists]")
        .attribute_steps.last.condition).to eq(c::Existence.new)

      expect(described_class.parse("obj.contributor[role.type='author' && organization.type='standards']")
        .attribute_steps.last.condition.operator).to eq("&&")
    end

    it "binds ! tightest, then comparison, then &&, then ||" do
      cond = described_class.parse("obj.x[a='1' || b='2' && c='3']").attribute_steps.last.condition
      expect(cond.operator).to eq("||")
      expect(cond.right.operator).to eq("&&")
    end

    it "honours parenthesised grouping" do
      cond = described_class.parse("obj.x[(a='1' || b='2') && c='3']").attribute_steps.last.condition
      expect(cond.operator).to eq("&&")
      expect(cond.left.operator).to eq("||")
    end

    it "rejects a malformed filter loudly rather than silently treating it as a charset" do
      expect { described_class.parse("obj.contributor[role.type=]") }
        .to raise_error(described_class::ParseError)
    end

    it "rejects operator-bearing charsets whose body is not a condition" do
      # The accepted regression. These were working charsets; the sniff now
      # claims them as filters and they fail to parse as conditions. Loud.
      ["pkg::x[a=b]", "pkg::Class[=]", "pkg::y[<]"].each do |input|
        expect { described_class.parse(input) }
          .to raise_error(described_class::ParseError), "expected #{input} to raise"
      end
    end

    it "reclassifies an operator-bearing charset whose body IS a condition" do
      # "Class[exists]" was a charset matching Classe/Classx. Its body parses
      # as a real condition, so it becomes a filter rather than a ParseError.
      # Still a break, but it surfaces at match? rather than at parse.
      path = described_class.parse("pkg::Class[exists]")
      expect(path).to be_a(Lutaml::Path::InstancePath)
      expect(path.conditions).to eq([Lutaml::Path::Condition::Existence.new])
      expect { path.match?(%w[pkg Classe]) }
        .to raise_error(Lutaml::Path::ResolutionError)
    end

    it "accepts the chained example from the README" do
      path = described_class.parse(
        "obj.contributor[role.type='author'].organization[name in ('ISO','IEC')].name"
      )
      expect(path.attribute_steps.map(&:name)).to eq(%w[contributor organization name])
      expect(path.conditions.length).to eq(2)
    end

    it "keeps a deep wildcard with a filter recognisable" do
      path = described_class.parse("obj.contributor.**[name='ISO']")
      expect(path.attribute_steps.last.deep_wildcard?).to be true
      expect(path.attribute_steps.last.condition).not_to be_nil
    end

    it "round-trips both path types through to_s" do
      [
        "Element",
        "::Package::Element",
        "Package::*::Base*",
        "core\\::types::Element",
        "obj.edition.number",
        "::Shapes::Rectangle.width",
        "obj.contributor[role.type='author']",
        "obj.x[(a='1' || b='2') && c='3']",
        "obj.docidentifier[type in ('ISBN','DOI')]",
        "obj.contributor[exists]"
      ].each do |input|
        parsed = described_class.parse(input)
        expect(described_class.parse(parsed.to_s)).to eq(parsed), "round-trip failed for #{input}"
      end
    end

    it "does not mistake a word operator inside an ordinary word for an operator" do
      # The sniff is token-aware. Without that, "in" inside "print", "and"
      # inside "standard", and "exists" inside "coexists" would claim these
      # ordinary character sets as filters and reject them.
      {
        "pkg::Class[print]" => "Class[print]",
        "pkg::Class[standard]" => "Class[standard]",
        "pkg::Class[sand]" => "Class[sand]",
        "pkg::Class[index]" => "Class[index]",
        "pkg::Class[min]" => "Class[min]",
        "pkg::Class[coexists]" => "Class[coexists]"
      }.each do |input, name|
        path = described_class.parse(input)
        expect(path).to be_a(Lutaml::Path::ElementPath), "expected #{input} to stay a charset"
        expect(path.segments.last.name).to eq(name)
      end
    end

    it "parses an in-list of any arity" do
      # A one-element list collapses to a bare Hash in Parslet rather than a
      # one-element Array. Getting that wrong raised TypeError straight out of
      # .parse, bypassing the ParseError rescue. The README only ever shows a
      # three-element list, so this was never exercised.
      {
        "obj.d[type in ('ISBN')]" => %w[ISBN],
        "obj.d[type in('ISBN')]" => %w[ISBN],
        "obj.d[type in ('ISBN','DOI')]" => %w[ISBN DOI],
        "obj.d[type in ('ISBN', 'ISSN', 'DOI')]" => %w[ISBN ISSN DOI],
        "obj.d[n in (1,2)]" => %w[1 2]
      }.each do |input, sources|
        expect(described_class.parse(input).conditions.first.literals.map(&:source))
          .to eq(sources), "failed for #{input}"
      end
    end

    it "allows a condition keyword to be used as an attribute name" do
      %w[exists in and].each do |word|
        path = described_class.parse("obj.x[#{word}='1']")
        expect(path.conditions.first.lhs.names).to eq([word]), "failed for #{word}"
      end
      # ...while a bare `exists` is still the existence predicate.
      expect(described_class.parse("obj.c[exists]").conditions.first)
        .to eq(Lutaml::Path::Condition::Existence.new)
    end

    it "raises ParseError, never SystemStackError, on a deeply nested filter" do
      # The condition grammar recurses through group/not/and/or. parse must
      # only ever raise ParseError, so the stack limit must not leak.
      [200, 500, 2000].each do |depth|
        expect { described_class.parse("obj.x[#{"(" * depth}exists]") }
          .to raise_error(described_class::ParseError), "leaked at depth #{depth}"
      end
    end

    it "does not mistake a word operator after a non-ASCII character" do
      # word_char must be Unicode-aware: with [A-Za-z0-9_], "é" is not a word
      # character, so the "in" in "[éin]" looks like the `in` operator.
      # The sniff tokenises with the same alphabet as attribute_ref, so any
      # character an identifier may contain -- including emoji -- keeps the
      # word whole. [[:word:]] alone is not enough: it excludes emoji.
      {
        "pkg::Class[éin]" => "Class[éin]",
        "pkg::Class[üand]" => "Class[üand]",
        "pkg::Class[标in]" => "Class[标in]",
        "pkg::Class[🙂in]" => "Class[🙂in]"
      }.each do |input, name|
        expect(described_class.parse(input).segments.last.name).to eq(name)
      end
    end

    it "round-trips a value containing an escaped quote" do
      path = described_class.parse("obj.x[a='O\\'Reilly']")
      expect(path.conditions.first.rhs.source).to eq("O'Reilly")
      expect(path.to_s).to eq("obj.x[a='O\\'Reilly']")
      expect(described_class.parse(path.to_s)).to eq(path)
    end

    it "parses an empty quoted value" do
      # Parslet yields [] rather than a slice for an empty repeat, so a
      # `simple` transform rule would never match and the node would stay raw.
      path = described_class.parse("obj.x[a='']")
      expect(path.conditions.first.rhs)
        .to eq(Lutaml::Path::Condition::Value.new("", :string))
      expect(path.to_s).to eq("obj.x[a='']")
      expect(described_class.parse(path.to_s)).to eq(path)
    end

    it "treats a dot inside a character set as literal, not a separator" do
      # An unclaimed bracket group is consumed whole, so "." and "::" inside a
      # character set do not split the segment. Both are working charsets on
      # main and must stay ElementPaths.
      {
        "pkg::Class[.]" => "Class[.]",
        "pkg::Class[a.b]" => "Class[a.b]",
        "pkg::Class[a::b]" => "Class[a::b]"
      }.each do |input, name|
        path = described_class.parse(input)
        expect(path).to be_a(Lutaml::Path::ElementPath), "expected #{input} to stay a charset"
        expect(path.segments.last.name).to eq(name)
      end
    end

    it "treats an escaped dot in a condition attribute as one name" do
      path = described_class.parse("obj.x[a\\.b='x']")
      expect(path.conditions.first.lhs.names).to eq(["a.b"])
      expect(described_class.parse("obj.x[role.type='x']").conditions.first.lhs.names)
        .to eq(%w[role type])
      # ...and it must survive a round-trip: rendering ["a.b"] as "a.b" would
      # re-parse as the two names ["a", "b"].
      expect(path.to_s).to eq("obj.x[a\\.b='x']")
      expect(described_class.parse(path.to_s)).to eq(path)
    end

    it "requires a token boundary after the word operator `exists`" do
      # Without it, "existsand b='2'" silently parses as `(exists and b='2')`.
      ["obj.x[existsand b='2']", "obj.x[existsand(exists)]"].each do |input|
        expect { described_class.parse(input) }
          .to raise_error(described_class::ParseError), "expected #{input} to raise"
      end
      # ...while every legitimate use of exists still works.
      expect(described_class.parse("obj.c[exists]").conditions.first)
        .to eq(Lutaml::Path::Condition::Existence.new)
      expect(described_class.parse("obj.c[!exists]").conditions.first)
        .to be_a(Lutaml::Path::Condition::Negation)
      expect(described_class.parse("obj.x[existsx='1']").conditions.first.lhs.names)
        .to eq(%w[existsx])
    end

    it "requires a token boundary after the word operator `and`" do
      # Without it, "android='2'" silently parses as `and` + the attribute
      # "roid" — a wrong result rather than an error.
      expect { described_class.parse("obj.x[a='1' android='2']") }
        .to raise_error(described_class::ParseError)
      # ...while `and` as a real operator, and `android` as an attribute name,
      # both still work.
      expect(described_class.parse("obj.x[a='1' and b='2']").conditions.first.right.lhs.names)
        .to eq(%w[b])
      expect(described_class.parse("obj.x[android='2']").conditions.first.lhs.names)
        .to eq(%w[android])
    end

    it "escapes the escape character, not just the delimiter" do
      # CodeQL: incomplete string escaping. Escaping only the delimiter leaves
      # a trailing backslash eating the closing quote ('abc\') and a name
      # ending in a backslash collapsing two names into one (a\.b).
      backslash = "\\"
      {
        "abc#{backslash}" => "value ending in a backslash",
        "a#{backslash}b" => "value containing a backslash",
        "a#{backslash}'b" => "backslash then quote",
        "a#{backslash}*b" => "backslash-star stays a literal for fnmatch"
      }.each do |source, why|
        value = Lutaml::Path::Condition::Value.new(source, :string)
        path = described_class.parse("obj.x[a=#{value}]")
        expect(path.conditions.first.rhs.source).to eq(source), "failed: #{why}"
      end

      {
        ["a#{backslash}", "b"] => "first name ends in a backslash",
        ["a#{backslash}b"] => "name contains a backslash",
        ["a.b", "c#{backslash}"] => "escaped dot and trailing backslash"
      }.each do |names, why|
        ref = Lutaml::Path::Condition::AttributeRef.new(names)
        path = described_class.parse("obj.x[#{ref}='z']")
        expect(path.conditions.first.lhs.names).to eq(names), "failed: #{why}"
      end
    end

    it "binds in and exists at the predicate level, like comparison" do
      # The README documents these exact groupings; pin them so the docs
      # cannot drift from the parser.
      membership = described_class.parse("obj.f[a in ('x','y') && b = 'z']").conditions.first
      expect(membership.operator).to eq("&&")
      expect(membership.left).to be_a(Lutaml::Path::Condition::Membership)
      expect(membership.right).to be_a(Lutaml::Path::Condition::Comparison)

      existence = described_class.parse("obj.f[exists && a = '1']").conditions.first
      expect(existence.left).to be_a(Lutaml::Path::Condition::Existence)

      # a = 'x' || b = 'y' && c = 'z'  =>  (a='x') || ((b='y') && (c='z'))
      mixed = described_class.parse("obj.f[a = 'x' || b = 'y' && c = 'z']").conditions.first
      expect(mixed.operator).to eq("||")
      expect(mixed.right.operator).to eq("&&")
    end

    it "raises error on empty segments" do
      expect { described_class.parse("pkg::::element") }.to raise_error(described_class::ParseError)
    end

    it "raises error on invalid syntax" do
      expect { described_class.parse("") }.to raise_error(described_class::ParseError)
    end
  end
end

RSpec.describe Lutaml::Path::PathSegment do
  it "matches exact names" do
    segment = described_class.new("Element")
    expect(segment.match?("Element")).to be true
    expect(segment.match?("Other")).to be false
  end

  it "matches patterns" do
    segment = described_class.new("Base*")
    expect(segment.match?("BaseClass")).to be true
    expect(segment.match?("Other")).to be false
  end

  it "derives pattern-ness from the name" do
    expect(described_class.new("Base*").pattern?).to be true
    expect(described_class.new("Element").pattern?).to be false
  end

  it "matches brace alternation" do
    segment = described_class.new("{Base,Case}")
    expect(segment.match?("Base")).to be true
    expect(segment.match?("Case")).to be true
    expect(segment.match?("Vase")).to be false
  end

  it "matches character sets, ranges, and negation" do
    expect(described_class.new("[abc]x").match?("bx")).to be true
    expect(described_class.new("[abc]x").match?("dx")).to be false
    expect(described_class.new("[a-z]*").match?("query")).to be true
    expect(described_class.new("[!CV]ase").match?("Base")).to be true
    expect(described_class.new("[!CV]ase").match?("Case")).to be false
  end

  it "recognizes a deep wildcard" do
    expect(described_class.new("**").deep_wildcard?).to be true
    expect(described_class.new("*").deep_wildcard?).to be false
    expect(described_class.new("a**b").deep_wildcard?).to be false
    expect(described_class.new("Element").deep_wildcard?).to be false
  end

  it "matches a double-asterisk substring as an ordinary glob" do
    segment = described_class.new("a**b")
    expect(segment.match?("axyb")).to be true
    expect(segment.match?("ab")).to be true
    expect(segment.match?("zb")).to be false
  end
end

RSpec.describe Lutaml::Path::ElementPath do
  it "matches path segments" do
    path = described_class.new([
                                 Lutaml::Path::PathSegment.new("pkg"),
                                 Lutaml::Path::PathSegment.new("*"),
                                 Lutaml::Path::PathSegment.new("Element")
                               ])

    expect(path.match?(%w[pkg sub Element])).to be true
    expect(path.match?(%w[other sub Element])).to be false
  end

  it "respects absolute paths" do
    path = described_class.new([
                                 Lutaml::Path::PathSegment.new("pkg"),
                                 Lutaml::Path::PathSegment.new("Element")
                               ], absolute: true)

    expect(path.match?(%w[pkg Element])).to be true
    expect(path.match?(%w[root pkg Element])).to be false
  end

  it "keeps single wildcard matching exactly one segment" do
    path = Lutaml::Path.parse("pkg::*::Element")
    expect(path.match?(%w[pkg sub Element])).to be true
    expect(path.match?(%w[pkg Element])).to be false
    expect(path.match?(%w[pkg a b Element])).to be false
  end

  it "matches deep patterns without exhausting the stack" do
    pattern = (["a"] + (["**"] * 5000) + ["b"]).join("::")
    path = Lutaml::Path.parse(pattern)

    expect { path.match?(%w[a x y z b]) }.not_to raise_error
    expect(path.match?(%w[a x y z b])).to be true
  end
end

RSpec.describe Lutaml::Path::AbstractPath do
  it "holds absoluteness and nothing else" do
    expect(described_class.new(absolute: true).absolute?).to be true
    expect(described_class.new.absolute?).to be false
  end

  it "does not declare match? — a subclass may be unable to honour it" do
    expect(described_class.instance_methods).not_to include(:match?)
    expect(described_class.instance_methods).not_to include(:segments)
  end

  it "is the supertype of ElementPath" do
    expect(Lutaml::Path::ElementPath.ancestors).to include(described_class)
  end
end

RSpec.describe Lutaml::Path::Condition do
  # NOT `C = Lutaml::Path::Condition` — a constant assigned inside a block
  # trips Lint/ConstantDefinitionInBlock and would turn rake red.
  def cond = Lutaml::Path::Condition

  it "renders a comparison the way the README writes it" do
    c = cond::Comparison.new(cond::AttributeRef.new(%w[role type]), "=",
                             cond::Value.new("author", :string))
    expect(c.to_s).to eq("role.type='author'")
  end

  it "renders membership and existence" do
    m = cond::Membership.new(cond::AttributeRef.new(%w[type]),
                             [cond::Value.new("ISBN", :string), cond::Value.new("DOI", :string)])
    expect(m.to_s).to eq("type in ('ISBN','DOI')")
    expect(cond::Existence.new.to_s).to eq("exists")
  end

  it "always parenthesises binary operations so structure round-trips" do
    inner = cond::BinaryOperation.new("||", cond::Existence.new, cond::Existence.new)
    outer = cond::BinaryOperation.new("&&", cond::Existence.new, inner)
    expect(outer.to_s).to eq("(exists && (exists || exists))")
  end

  it "compares by value" do
    a = cond::Comparison.new(cond::AttributeRef.new(%w[a]), "=", cond::Value.new("x", :string))
    b = cond::Comparison.new(cond::AttributeRef.new(%w[a]), "=", cond::Value.new("x", :string))
    expect(a).to eq(b)
    expect(a.hash).to eq(b.hash)
    expect({ a => 1 }[b]).to eq(1)
  end

  it "is frozen — a parsed AST must be immutable" do
    v = cond::Value.new("x", :string)
    expect(v).to be_frozen
    expect { v.source = "y" }.to raise_error(FrozenError)
  end

  it "freezes deeply — the collections and strings it owns, not just the Struct" do
    # A shallow freeze leaves `names << "x"` working, which also silently
    # invalidates the Struct's own hash.
    ref = cond::AttributeRef.new(["role"])
    val = cond::Value.new("x", :string)
    member = cond::Membership.new(ref, [val])
    cmp = cond::Comparison.new(ref, "=", val)
    binary = cond::BinaryOperation.new("&&", cmp, cmp)
    expect { ref.names << "X" }.to raise_error(FrozenError)
    expect { ref.names.first << "X" }.to raise_error(FrozenError)
    expect { val.source << "!" }.to raise_error(FrozenError)
    expect { member.literals << val }.to raise_error(FrozenError)
    expect { cmp.op << "!" }.to raise_error(FrozenError)
    expect { binary.operator << "!" }.to raise_error(FrozenError)
  end

  it "derives pattern? from the raw source, only for strings" do
    expect(cond::Value.new("stand*", :string).pattern?).to be true
    expect(cond::Value.new("standards", :string).pattern?).to be false
    expect(cond::Value.new("30", :number).pattern?).to be false
  end
end

RSpec.describe Lutaml::Path::Step do
  def seg(name) = Lutaml::Path::PathSegment.new(name)

  it "delegates name, pattern? and deep_wildcard? to its segment" do
    step = described_class.new(seg("**"))
    expect(step.name).to eq("**")
    expect(step.deep_wildcard?).to be true
    expect(described_class.new(seg("Base*")).pattern?).to be true
  end

  it "keeps deep_wildcard? true when a filter is attached" do
    step = described_class.new(seg("**"), condition: Lutaml::Path::Condition::Existence.new)
    expect(step.deep_wildcard?).to be true
  end

  it "never answers match? — it can carry a filter it cannot evaluate" do
    expect(described_class.instance_methods).not_to include(:match?)
  end

  it "renders its own brackets" do
    expect(described_class.new(seg("contributor")).to_s).to eq("contributor")
    step = described_class.new(seg("contributor"), condition: Lutaml::Path::Condition::Existence.new)
    expect(step.to_s).to eq("contributor[exists]")
  end

  it "compares by value" do
    expect(described_class.new(seg("a"))).to eq(described_class.new(seg("a")))
    expect(described_class.new(seg("a"))).not_to eq(described_class.new(seg("b")))
  end
end

RSpec.describe Lutaml::Path::InstancePath do
  def step(name) = Lutaml::Path::Step.new(Lutaml::Path::PathSegment.new(name))

  it "is an AbstractPath" do
    expect(described_class.ancestors).to include(Lutaml::Path::AbstractPath)
  end

  it "separates the base steps from the attribute steps" do
    path = described_class.new(base_steps: [step("Shapes"), step("Rectangle")],
                               attribute_steps: [step("width")], absolute: true)
    expect(path.absolute?).to be true
    expect(path.base_steps.map(&:name)).to eq(%w[Shapes Rectangle])
    expect(path.attribute_steps.map(&:name)).to eq(%w[width])
    expect(path.steps.map(&:name)).to eq(%w[Shapes Rectangle width])
  end

  it "raises a scoped ResolutionError from match?" do
    path = described_class.new(base_steps: [step("obj")], attribute_steps: [step("title")])
    expect { path.match?(%w[obj title]) }
      .to raise_error(Lutaml::Path::ResolutionError, /parsed but not resolved/)
  end

  # ResolutionError descends from StandardError, so a caller guarding a
  # mixed batch of paths degrades instead of crashing. NotImplementedError
  # is a ScriptError and would escape this rescue.
  it "is catchable by a bare rescue, unlike NotImplementedError" do
    path = described_class.new(base_steps: [step("obj")], attribute_steps: [step("title")])
    caught = begin
      path.match?(%w[obj title])
    rescue StandardError
      :rescued
    end
    expect(caught).to eq(:rescued)
  end
end
