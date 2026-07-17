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
end
