RSpec.describe Grundit::ApplicationPolicy do
  describe "#default_permissions?" do
    it "grants access to a user whose role is in the default list" do
      Grundit.configure { |c| c.default_permission_roles = %w[super_admin admin] }

      user = TestUser.new(:role => "super_admin")
      policy = Grundit::ApplicationPolicy.new(user)

      expect(policy.default_permissions?).to be true
    end

    it "denies access to a user whose role is not in the default list" do
      Grundit.configure { |c| c.default_permission_roles = %w[super_admin admin] }

      user = TestUser.new(:role => "user")
      policy = Grundit::ApplicationPolicy.new(user)

      expect(policy.default_permissions?).to be false
    end

    it "allows additional roles" do
      Grundit.configure { |c| c.default_permission_roles = %w[super_admin] }

      user = TestUser.new(:role => "editor")
      policy = Grundit::ApplicationPolicy.new(user)

      expect(policy.default_permissions?(:additional_roles => [:editor])).to be true
    end

    it "excludes specified roles" do
      Grundit.configure { |c| c.default_permission_roles = %w[super_admin admin] }

      user = TestUser.new(:role => "admin")
      policy = Grundit::ApplicationPolicy.new(user)

      expect(policy.default_permissions?(:except_roles => [:admin])).to be false
    end

    after { Grundit.reset_configuration! }
  end

  describe "CRUD stubs" do
    it "delegates show? to default_permissions?" do
      Grundit.configure { |c| c.default_permission_roles = %w[super_admin] }

      admin = TestUser.new(:role => "super_admin")
      user = TestUser.new(:role => "user")

      expect(Grundit::ApplicationPolicy.new(admin).show?).to be true
      expect(Grundit::ApplicationPolicy.new(user).show?).to be false
    end

    it "delegates create? to default_permissions?" do
      Grundit.configure { |c| c.default_permission_roles = %w[super_admin] }

      admin = TestUser.new(:role => "super_admin")

      expect(Grundit::ApplicationPolicy.new(admin).create?).to be true
    end

    it "delegates update? to default_permissions?" do
      Grundit.configure { |c| c.default_permission_roles = %w[super_admin] }

      admin = TestUser.new(:role => "super_admin")

      expect(Grundit::ApplicationPolicy.new(admin).update?).to be true
    end

    it "delegates destroy? to default_permissions?" do
      Grundit.configure { |c| c.default_permission_roles = %w[super_admin] }

      admin = TestUser.new(:role => "super_admin")

      expect(Grundit::ApplicationPolicy.new(admin).destroy?).to be true
    end

    after { Grundit.reset_configuration! }
  end

  describe "Scope" do
    it "returns all records by default" do
      Widget.create!(:name => "A", :owner_id => 1)
      Widget.create!(:name => "B", :owner_id => 2)
      user = TestUser.new(:role => "super_admin")

      scope = Grundit::ApplicationPolicy::Scope.new(user, Widget.all)

      expect(scope.resolve.count).to eq Widget.count
    end
  end

  describe "#current_user_role" do
    it "prefers role_for_session when available" do
      user = TestUser.new(:role => "admin")

      def user.role_for_session
        "super_admin"
      end

      Grundit.configure { |c| c.default_permission_roles = %w[super_admin] }
      policy = Grundit::ApplicationPolicy.new(user)

      expect(policy.show?).to be true
    end

    it "falls back to role when role_for_session is not defined" do
      user = Object.new

      def user.role
        "admin"
      end

      def user.present?
        true
      end

      Grundit.configure { |c| c.default_permission_roles = %w[admin] }
      policy = Grundit::ApplicationPolicy.new(user)

      expect(policy.show?).to be true
    end

    after { Grundit.reset_configuration! }
  end

  describe "constructor with record" do
    it "sets the record when the scope can find it" do
      widget = Widget.create!(:name => "Visible", :owner_id => 1)
      user = TestUser.new(:role => "super_admin")
      policy = WidgetPolicy.new(user, widget)

      expect(policy.record).to eq widget
    end

    it "raises when the scope cannot find the record" do
      widget = Widget.create!(:name => "Hidden", :owner_id => 999)
      user = TestUser.new(:role => "user", :id => 1)

      expect {
        WidgetPolicy.new(user, widget)
      }.to raise_error(/not found/)
    end
  end
end
