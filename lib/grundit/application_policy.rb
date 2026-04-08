# Grundit::ApplicationPolicy is the base class for all authorization policies.
#
# It provides:
# - A constructor that verifies record visibility through scope resolution
# - default_permissions? helper based on configurable role lists
# - CRUD action stubs (show?, create?, update?, destroy?)
# - A Scope class that defines the universe of records visible to a user
#
# The Scope is the first line of defense. It defines the world of records that
# a given user is allowed to see at all. When auth() is called with a single
# record, the constructor runs that record through the Scope first — if the
# user cannot see the record, the policy action (show?, update?, etc.) is
# never reached. This means the Scope acts as a hard visibility boundary,
# and the action methods only refine permissions within that visible set.
#
# Example:
#   class UserPolicy < Grundit::ApplicationPolicy
#     def show?
#       user.admin? || record.id == user.id
#     end
#
#     # The Scope defines which users this user can see at all.
#     # If a record is not in this set, no action method will ever run for it.
#     class Scope < Grundit::ApplicationPolicy::Scope
#       def resolve
#         if user.admin?
#           return scope.all
#         end
#
#         scope.where(:id => user.id)
#       end
#     end
#   end

module Grundit
  class ApplicationPolicy
    attr_reader :user, :record, :options

    def initialize(user, record = nil, options = {})
      @user = user
      @options = options

      begin
        if record.present?
          @record = if record.new_record?
                      record
                    else
                      self.class::Scope.new(user, record.class.all).resolve.find(record.id)
                    end
        end
      rescue StandardError => _error
        raise "#{record.class.name}##{record.id} not found. Refer to #{self.class.name}##{options[:action]}?"
      end
    end

    # Check whether the current user's role is in the allowed set.
    #
    # Options:
    #   additional_roles: - extra roles to allow beyond the configured defaults
    #   except_roles:     - roles to explicitly exclude
    def default_permissions?(additional_roles: [], except_roles: [])
      roles_allowed = (Grundit.configuration.default_permission_roles + additional_roles.collect(&:to_s)).uniq

      (roles_allowed - except_roles.uniq.collect(&:to_s)).include?(current_user_role)
    end

    def show?
      default_permissions?
    end

    def create?
      default_permissions?
    end

    def update?
      default_permissions?
    end

    def destroy?
      default_permissions?
    end

    # Scope defines the universe of records visible to a given user. It serves
    # two purposes:
    #
    # 1. auth_index() uses it to filter collections down to what the user can see.
    # 2. The policy constructor uses it to verify that a single record is visible.
    #    If the record falls outside the scope, the policy raises immediately —
    #    the action method (show?, update?, etc.) is never called.
    #
    # Override #resolve in your policy's Scope subclass to define visibility.
    class Scope
      attr_reader :user, :scope

      def initialize(user, scope)
        @user = user
        @scope = scope
      end

      def resolve
        scope.all
      end
    end

    private

    def current_user_role
      if user.respond_to?(:role_for_session)
        return user.role_for_session.to_s
      end

      user.role.to_s
    end
  end
end
