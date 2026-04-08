class GrunditQuery < GraphQL::Schema::Object
  include Grundit::Authorization

  def self.field(*args, authorize: true, **kwargs, &block)
    field_name = args[0]

    super(*args, **kwargs) do
      extension(Grundit::EnforcementExtension,
                :authorize => authorize,
                :field_name => field_name)
      instance_eval(&block) if block
    end
  end
end
