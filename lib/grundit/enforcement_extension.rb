# Grundit::EnforcementExtension is a graphql-ruby field extension intended for
# top-level query fields and mutation fields. It ensures each resolver calls
# auth() or auth_index() before returning data.
#
# This powers GrunditQuery and GrunditMutation automatically. You only need to
# wire it manually if you are not deriving from those base classes.
#
# Manual usage — override `self.field` in your QueryType or BaseMutation:
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

module Grundit
  class EnforcementExtension < GraphQL::Schema::FieldExtension

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
