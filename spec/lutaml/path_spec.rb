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

    xit "parses paths with patterns" do
      path = described_class.parse("Package::*::Base*")
      expect(path.segments.map(&:pattern?)).to eq([false, true, true])
      expect(path.segments.map(&:name)).to eq(["Package", "*", "Base*"])
    end

    it "handles escaped separators" do
      path = described_class.parse("core\\::types::Element")
      expect(path.segments.map(&:name)).to eq(["core::types", "Element"])
    end

    it "handles Unicode characters" do
      path = described_class.parse("建物::窓::ガラス")
      expect(path.segments.map(&:name)).to eq(%w[建物 窓 ガラス])
    end

    xit "handles glob patterns" do
      path = described_class.parse("pkg::{a,b}*::[0-9]*")
      expect(path.segments.last.pattern?).to be true
      expect(path.match?(%w[pkg btest 123])).to be true
    end

    it "raises error on empty segments" do
      expect { described_class.parse("pkg::::element") }.to raise_error(described_class::ParseError)
    end

    it "raises error on invalid syntax" do
      expect { described_class.parse("") }.to raise_error(described_class::ParseError)
    end
  end

  describe Lutaml::Path::PathSegment do
    it "matches exact names" do
      segment = described_class.new("Element")
      expect(segment.match?("Element")).to be true
      expect(segment.match?("Other")).to be false
    end

    it "matches patterns" do
      segment = described_class.new("Base*", is_pattern: true)
      expect(segment.match?("BaseClass")).to be true
      expect(segment.match?("Other")).to be false
    end
  end

  describe Lutaml::Path::ElementPath do
    it "matches path segments" do
      path = described_class.new([
                                   Lutaml::Path::PathSegment.new("pkg"),
                                   Lutaml::Path::PathSegment.new("*", is_pattern: true),
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
end
