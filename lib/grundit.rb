require "active_support/concern"
require "active_support/core_ext/string/inflections"
require "graphql"

require_relative "grundit/version"
require_relative "grundit/authorization"
require_relative "grundit/enforcement_extension"
require_relative "grundit/application_policy"
require_relative "grundit/grundit_query"
require_relative "grundit/grundit_mutation"

module Grundit
  class Configuration
    attr_accessor :default_permission_roles, :excluded_fields

    def initialize
      @default_permission_roles = %w[super_admin account_admin organization_admin]
      @excluded_fields = %w[node nodes __schema __type]
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
