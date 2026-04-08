# Grundit::EnforcementExtension is a graphql-ruby field extension that ensures
# every resolver calls auth() or auth_index() before returning data.
#
# Usage — override `self.field` in your QueryType or BaseMutation:
#
#   class Types::QueryType < Types::BaseObject
#     def self.field(*args, authorize: true, **kwargs, &block)
#       field_name = args[0]
#
#       super(*args, **kwargs) do
#         extension(Grundit::EnforcementExtension, :authorize => authorize, :field_name => field_name)
#         instance_eval(&block) if block
#       end
#     end
#   end
#
# Options passed via `extension()`:
#   :authorize  - set to false to skip enforcement for a specific field
#   :field_name - the field name (used in error messages)
#   :before_resolve - an optional callable (lambda/proc) receiving (context, field_name)
#                     that runs before the resolver. Raise to block execution.

module Grundit
  class EnforcementExtension < GraphQL::Schema::FieldExtension
    def resolve(object:, arguments:, context:)
      field_name = options[:field_name].to_s

      if options[:before_resolve] && !excluded_field?(field_name)
        options[:before_resolve].call(context, field_name)
      end

      yield(object, arguments)
    end

    def after_resolve(value:, context:, **_rest)
      if !options[:authorize]
        return value
      end

      field_name = options[:field_name].to_s

      if excluded_field?(field_name)
        return value
      end

      if !context[:authorization_called]
        raise GraphQL::ExecutionError,
              "Authorization required: Field '#{field_name}' must call auth() or auth_index() before returning"
      end

      # Reset the flag for the next field resolution.
      context[:authorization_called] = false

      value
    end

    private

    def excluded_field?(field_name)
      Grundit.configuration.excluded_fields.include?(field_name)
    end
  end
end
