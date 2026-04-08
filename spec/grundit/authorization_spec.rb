RSpec.describe Grundit::Authorization do
  let(:admin) { TestUser.new(:role => "super_admin") }
  let(:regular_user) { TestUser.new(:role => "user", :id => 42) }

  describe "#auth" do
    it "returns the object when authorized" do
      widget = Widget.create!(:name => "Gadget", :owner_id => admin.id)
      harness = AuthorizationTestHarness.new(admin)

      result = harness.auth(widget)

      expect(result).to eq widget
    end

    it "defaults to the show? policy action" do
      widget = Widget.create!(:name => "Gadget", :owner_id => regular_user.id)
      harness = AuthorizationTestHarness.new(regular_user)

      # WidgetPolicy#show? returns true for everyone.
      result = harness.auth(widget)

      expect(result).to eq widget
    end

    it "accepts a specified policy action" do
      widget = Widget.create!(:name => "Gadget", :owner_id => admin.id)
      harness = AuthorizationTestHarness.new(admin)

      result = harness.auth(widget, :action => :update)

      expect(result).to eq widget
    end

    it "raises GraphQL::ExecutionError when the policy denies access" do
      widget = Widget.create!(:name => "Secret", :owner_id => admin.id)
      harness = AuthorizationTestHarness.new(admin)

      expect {
        harness.auth(widget, :action => :denied_action)
      }.to raise_error(GraphQL::ExecutionError, /Not authorized/)
    end

    it "accepts an explicit policy class" do
      widget = Widget.create!(:name => "Gadget", :owner_id => admin.id)
      harness = AuthorizationTestHarness.new(admin)

      result = harness.auth(widget, :policy_class => WidgetPolicy)

      expect(result).to eq widget
    end

    it "accepts a symbolized policy class" do
      widget = Widget.create!(:name => "Gadget", :owner_id => admin.id)
      harness = AuthorizationTestHarness.new(admin)

      result = harness.auth(widget, :policy_class => :widget)

      expect(result).to eq widget
    end

    it "marks authorization as called" do
      widget = Widget.create!(:name => "Gadget", :owner_id => admin.id)
      harness = AuthorizationTestHarness.new(admin)

      expect(harness.authorization_called?).to be false

      harness.auth(widget)

      expect(harness.authorization_called?).to be true
    end

    it "forwards custom options to the policy" do
      widget = Widget.create!(:name => "Gadget", :owner_id => admin.id)
      harness = AuthorizationTestHarness.new(admin)

      # Custom options should not raise; they pass through to the policy's options hash.
      result = harness.auth(widget, :extra_context => "something")

      expect(result).to eq widget
    end
  end

  describe "#auth_index" do
    it "returns scoped records for a super_admin" do
      widget_a = Widget.create!(:name => "A", :owner_id => 1)
      widget_b = Widget.create!(:name => "B", :owner_id => 2)
      harness = AuthorizationTestHarness.new(admin)

      result = harness.auth_index(:widget, Widget.all)

      expect(result).to include(widget_a, widget_b)
    end

    it "scopes records for a regular user" do
      own_widget = Widget.create!(:name => "Mine", :owner_id => regular_user.id)
      Widget.create!(:name => "Theirs", :owner_id => 999)
      harness = AuthorizationTestHarness.new(regular_user)

      result = harness.auth_index(:widget, Widget.all)

      expect(result).to contain_exactly(own_widget)
    end

    it "accepts an explicit policy class" do
      Widget.create!(:name => "A", :owner_id => admin.id)
      harness = AuthorizationTestHarness.new(admin)

      result = harness.auth_index(:widget, Widget.all, :policy_class => WidgetPolicy)

      expect(result).not_to be_empty
    end

    it "accepts a symbolized policy class" do
      Widget.create!(:name => "A", :owner_id => admin.id)
      harness = AuthorizationTestHarness.new(admin)

      result = harness.auth_index(:widget, Widget.all, :policy_class => :widget)

      expect(result).not_to be_empty
    end

    it "marks authorization as called" do
      harness = AuthorizationTestHarness.new(admin)

      expect(harness.authorization_called?).to be false

      harness.auth_index(:widget, Widget.all)

      expect(harness.authorization_called?).to be true
    end
  end

  describe "#mark_authorized!" do
    it "sets the authorization flag in context" do
      harness = AuthorizationTestHarness.new(admin)

      harness.mark_authorized!

      expect(harness.context[:authorization_called]).to be true
    end
  end

  describe "#current_user" do
    it "returns the user from context" do
      harness = AuthorizationTestHarness.new(admin)

      expect(harness.current_user).to eq admin
    end
  end
end
