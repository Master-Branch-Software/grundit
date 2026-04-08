RSpec.describe Grundit::EnforcementExtension do
  # Build a minimal schema to exercise the extension in a real graphql-ruby pipeline.
  let(:test_schema) do
    enforcement_ext = Grundit::EnforcementExtension

    query_type = Class.new(GraphQL::Schema::Object) do
      graphql_name "Query"
      include Grundit::Authorization

      field :authorized_field, String, null: true do
        extension(enforcement_ext, :authorize => true, :field_name => "authorized_field")
      end

      define_method(:authorized_field) do
        mark_authorized!

        "allowed"
      end

      field :unauthorized_field, String, null: true do
        extension(enforcement_ext, :authorize => true, :field_name => "unauthorized_field")
      end

      define_method(:unauthorized_field) do
        "forgot to call auth"
      end

      field :skipped_field, String, null: true do
        extension(enforcement_ext, :authorize => false, :field_name => "skipped_field")
      end

      define_method(:skipped_field) do
        "no auth needed"
      end

      field :node_field, String, null: true do
        extension(enforcement_ext, :authorize => true, :field_name => "node")
      end

      define_method(:node_field) do
        "relay node"
      end
    end

    Class.new(GraphQL::Schema) do
      query(query_type)
    end
  end

  def execute(query_string, context: {})
    test_schema.execute(query_string, :context => context)
  end

  it "allows fields that call mark_authorized!" do
    result = execute("{ authorizedField }")

    expect(result["data"]["authorizedField"]).to eq "allowed"
    expect(result["errors"]).to be_nil
  end

  it "raises when a field does not call auth" do
    result = execute("{ unauthorizedField }")

    expect(result["errors"].first["message"]).to match(/Authorization required.*unauthorized_field/)
  end

  it "skips enforcement when authorize is false" do
    result = execute("{ skippedField }")

    expect(result["data"]["skippedField"]).to eq "no auth needed"
    expect(result["errors"]).to be_nil
  end

  it "skips enforcement for excluded fields like node" do
    result = execute("{ nodeField }")

    expect(result["data"]["nodeField"]).to eq "relay node"
    expect(result["errors"]).to be_nil
  end


  it "resets the authorization flag after a successful field" do
    context = {}
    result = execute("{ authorizedField }", :context => context)

    expect(result["errors"]).to be_nil
    expect(context[:authorization_called]).to be false
  end
end
