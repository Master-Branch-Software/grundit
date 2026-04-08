RSpec.describe "Grundit base classes" do
  let(:user) { TestUser.new(:role => "super_admin") }

  it "GrunditQuery provides auth() to query fields" do
    query_type = Class.new(GrunditQuery) do
      graphql_name "BaseClassQueryAuth"

      field :widget_name, String, null: false do
        argument :id, GraphQL::Types::ID, required: true
      end

      define_method(:widget_name) do |id:|
        auth(Widget.find(id)).name
      end
    end

    schema = Class.new(GraphQL::Schema) do
      query(query_type)
    end

    widget = Widget.create!(:name => "Visible widget", :owner_id => user.id)
    result = schema.execute("{ widgetName(id: #{widget.id}) }", :context => { :current_user => user })

    expect(result["data"]["widgetName"]).to eq "Visible widget"
    expect(result["errors"]).to be_nil
  end

  it "GrunditQuery enforces authorization on query fields" do
    query_type = Class.new(GrunditQuery) do
      graphql_name "BaseClassQueryEnforcement"

      field :oops, String, null: false

      define_method(:oops) do
        "forgot auth"
      end
    end

    schema = Class.new(GraphQL::Schema) do
      query(query_type)
    end

    result = schema.execute("{ oops }", :context => { :current_user => user })

    expect(result["errors"].first["message"]).to match(/Authorization required/)
  end

  it "GrunditMutation provides auth() and enforcement to mutations" do
    mutation_class = Class.new(GrunditMutation) do
      graphql_name "RenameWidget"
      argument :id, GraphQL::Types::ID, required: true
      argument :name, String, required: true

      field :widget_name, String, null: false

      define_method(:resolve) do |id:, name:|
        widget = auth(Widget.find(id), :action => :update)
        widget.update!(:name => name)

        { :widget_name => widget.name }
      end
    end

    mutation_type = Class.new(GraphQL::Schema::Object) do
      graphql_name "Mutation"

      field :rename_widget, mutation: mutation_class
    end

    query_type = Class.new(GraphQL::Schema::Object) do
      graphql_name "Query"

      field :noop, String, null: false

      define_method(:noop) do
        "ok"
      end
    end

    schema = Class.new(GraphQL::Schema) do
      query(query_type)
      mutation(mutation_type)
    end

    widget = Widget.create!(:name => "Before", :owner_id => user.id)
    result = schema.execute(
      "mutation { renameWidget(input: { id: #{widget.id}, name: \"After\" }) { widgetName } }",
      :context => { :current_user => user }
    )

    expect(result["data"]["renameWidget"]["widgetName"]).to eq "After"
    expect(result["errors"]).to be_nil
  end
end
