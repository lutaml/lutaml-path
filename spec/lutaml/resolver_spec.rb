# frozen_string_literal: true

require "spec_helper"

# The resolution specs exercise real lutaml-model instances. The gem
# works without lutaml-model loaded (the resolver's model branch is
# defined?-guarded), so when the dependency cannot load — an adapter
# gem missing on an exotic platform, say — the suite skips instead of
# failing at file load.
begin
  require "lutaml/model"
  LUTAML_MODEL_AVAILABLE = true
rescue LoadError, StandardError
  LUTAML_MODEL_AVAILABLE = false
end

# Conformance corpus for RS 3002 "LutaML path for instance data",
# resolved against real lutaml-model instances shaped like the
# specification's own examples (contributor / organization / role /
# docidentifier / date).
# The model-fixture stack mirrors the specification's example model
# (contributor / organization / role / docidentifier); it is the
# conformance corpus, not incidental setup.
RSpec.describe "Lutaml::Path.resolve over lutaml-model instances" do
  before do
    skip "lutaml-model is not loadable in this bundle" unless LUTAML_MODEL_AVAILABLE
  end
  let(:role_class) do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :type, :string

      json { map "type", to: :type }
    end
    stub_const("LpSpec::Role", klass)
    klass
  end

  let(:organization_class) do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :type, :string

      json do
        map "name", to: :name
        map "type", to: :type
      end
    end
    stub_const("LpSpec::Organization", klass)
    klass
  end

  let(:contributor_class) do
    role = role_class
    org = organization_class
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :role, role
      attribute :organization, org

      json do
        map "role", to: :role
        map "organization", to: :organization
      end
    end
    stub_const("LpSpec::Contributor", klass)
    klass
  end

  let(:docidentifier_class) do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :type, :string
      attribute :value, :string

      json do
        map "type", to: :type
        map "id", to: :value
      end
    end
    stub_const("LpSpec::Docidentifier", klass)
    klass
  end

  let(:document_class) do
    contributor = contributor_class
    identifier = docidentifier_class
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :title, :string
      attribute :contributor, contributor, collection: true
      attribute :docidentifier, identifier, collection: true

      json do
        map "title", to: :title
        map "contributor", to: :contributor
        map "docidentifier", to: :docidentifier
      end
    end
    stub_const("LpSpec::Document", klass)
    klass
  end

  let(:document) do
    document_class.from_json(
      <<~JSON
        {
          "title": "Standard X",
          "contributor": [
            {"role": {"type": "publisher"},
             "organization": {"name": "ISO", "type": "standards"}},
            {"role": {"type": "author"},
             "organization": {"name": "ACME", "type": "company"}},
            {"role": {"type": "author"},
             "organization": {"name": "IEC", "type": "standards"}}
          ],
          "docidentifier": [
            {"type": "ISBN", "id": "978-1"},
            {"type": "ISSN", "id": "1234-5"},
            {"type": "DOI", "id": "10.1/x"}
          ]
        }
      JSON
    )
  end

  def resolve(path)
    Lutaml::Path.resolve(document, path)
  end

  it "resolves a simple attribute chain to a single value" do
    expect(resolve("title")).to eq("Standard X")
  end

  it "resolves a collection attribute to its elements" do
    expect(resolve("contributor").length).to eq(3)
  end

  it "resolves a nested chain through a collection element" do
    expect(resolve("contributor[role.type='publisher'].organization.name"))
      .to eq(["ISO"])
  end

  it "filters with multiple conditions" do
    expect(resolve("contributor[role.type='author' && organization.type='standards'].organization.name")
      .sort).to eq(%w[IEC])
  end

  it "filters with list membership" do
    expect(resolve("docidentifier[type in ('ISBN','ISSN')].value").sort)
      .to eq(%w[1234-5 978-1])
  end

  it "filters with negation" do
    expect(resolve("docidentifier[type!='ISBN'].value").sort)
      .to eq(["10.1/x", "1234-5"])
  end

  it "filters with existence" do
    expect(resolve("contributor[exists].organization.name").sort)
      .to eq(%w[ACME IEC ISO])
  end

  it "matches wildcard condition values" do
    expect(resolve("contributor[organization.type='stand*'].organization.name").sort)
      .to eq(%w[IEC ISO])
  end

  it "resolves wildcard segments across the collection" do
    expect(resolve("*.type").compact.sort)
      .to eq(%w[DOI ISBN ISSN])
  end

  it "resolves a deep hierarchy wildcard with a filter" do
    expect(resolve("contributor.**[name='ISO']")).to contain_exactly(
      an_object_having_attributes(name: "ISO")
    )
  end

  it "resolves against plain hashes the same way" do
    data = { "contributor" => [{ "role" => { "type" => "publisher" } }] }

    expect(Lutaml::Path.resolve(data, "contributor[role.type='publisher']")).not_to be_empty
    expect(Lutaml::Path.resolve(data, "contributor.role.type")).to eq("publisher")
  end
end
