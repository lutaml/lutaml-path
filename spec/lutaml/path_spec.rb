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
