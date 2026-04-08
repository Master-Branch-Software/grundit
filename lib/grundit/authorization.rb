# Grundit::Authorization provides auth() and auth_index() for GraphQL query
# and mutation resolvers. This is not intended for field-level authorization —
# it operates at the resolver level where you fetch and return data.
#
# Include this module where your top-level query and mutation resolvers live —
# usually Types::QueryType and Mutations::BaseMutation. Call auth() or
# auth_index() inside query fields and mutation resolvers to gate access
# through Pundit-style policy classes.
#
# Example:
#   class Types::QueryType < Types::BaseObject
#     include Grundit::Authorization
#   end
#
#   # In a query resolver:
#   def user(id:)
#     auth(User.find(id))
#   end
#
#   # In an index resolver:
#   def users
#     auth_index(:user, User.all)
#   end

module Grundit
  module Authorization
    def current_user
      context[:current_user]
    end

    def mark_authorized!
      context[:authorization_called] = true
    end

    def authorization_called?
      context[:authorization_called] == true
    end

    # Authorize a single object.
    #
    # In its simplest use, pass the object in question. A policy class is determined
    # from the object's class and its #show? method is called.
    #
    # Options:
    #   :policy_class - explicit policy class (UserPolicy) or symbol (:user)
    #   :action       - policy method to call, without the question mark (default: :show)
    #
    # Any additional options are forwarded to the policy constructor, making them
    # available inside the policy for more complex permission checks.
    #
    # Examples:
    #   auth(record)
    #   auth(record, :action => :update)
    #   auth(record, :policy_class => ThingPolicy, :action => :update)
    #   auth(record, :policy_class => :thing, :action => :complex_check, :extra_context => value)
    def auth(object, options = {})
      mark_authorized!

      default_options = {
        :current_user => current_user,
        :action => :show,
        :policy_class => nil
      }

      opts = default_options.merge(options)

      # Custom options to be passed to and used by the policy.
      custom_options = opts.except(*default_options.keys)

      policy = resolve_policy_class(object, custom_options).new(opts[:current_user], object, custom_options)

      if !policy.send("#{opts[:action]}?")
        raise GraphQL::ExecutionError, "Not authorized."
      end

      object
    end

    # Authorize a collection via scope resolution.
    #
    # The policy_class can be the class itself (UserPolicy), a symbol (:user),
    # or left to be inferred from the collection.
    #
    # Examples:
    #   auth_index(:user, User.all)
    #   auth_index(:user, User.all, :policy_class => UserPolicy)
    def auth_index(policy_class, object_array, options = {})
      mark_authorized!

      default_options = {
        :policy_class => policy_class,
        :current_user => current_user
      }

      opts = default_options.merge(options)

      resolve_policy_class(object_array, opts)::Scope.new(opts[:current_user], object_array).resolve
    end

    private

    # Determine the policy class from an explicit option, a symbol, or the object's class.
    def resolve_policy_class(object, options)
      if options[:policy_class]
        if options[:policy_class].is_a?(Symbol)
          "#{options[:policy_class].to_s.camelize}Policy".constantize
        else
          options[:policy_class]
        end
      else
        "#{object.class.name}Policy".constantize
      end
    end
  end
end
