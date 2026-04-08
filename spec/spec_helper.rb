require "active_record"
require "grundit"

ActiveRecord::Base.establish_connection(
  :adapter => "sqlite3",
  :database => ":memory:"
)

ActiveRecord::Schema.define do
  create_table :widgets, :force => true do |t|
    t.string :name
    t.integer :owner_id
  end
end

# Minimal user stub that quacks enough for policies.
class TestUser
  attr_accessor :role, :id

  def initialize(role: "user", id: 1)
    @role = role
    @id = id
  end

  def super_admin?
    role == "super_admin"
  end

  def admin?
    role == "admin"
  end
end

# A real ActiveRecord model for policy scope testing.
class Widget < ActiveRecord::Base
end

# A policy for Widget.
class WidgetPolicy < Grundit::ApplicationPolicy
  def show?
    true
  end

  def create?
    user.admin? || user.super_admin?
  end

  def update?
    user.admin? || user.super_admin?
  end

  def custom_action?
    user.role == "custom_role"
  end

  def denied_action?
    false
  end

  class Scope < Grundit::ApplicationPolicy::Scope
    def resolve
      if user.super_admin?
        return scope.all
      end

      scope.where(:owner_id => user.id)
    end
  end
end

# A harness that mimics a GraphQL resolver with Grundit::Authorization mixed in.
class AuthorizationTestHarness
  include Grundit::Authorization

  def initialize(user)
    @context = { :current_user => user }
  end

  def context
    @context
  end
end

RSpec.configure do |config|
  config.around(:each) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
