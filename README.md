# Grundit

A Pundit-compatible, GraphQL-centric authorization framework for Rails.

Grundit gives you three things:

1. **`auth()` / `auth_index()`** — authorize single objects or collections
   from any GraphQL resolver using Pundit-style policy classes.
2. **Enforcement** — a graphql-ruby field extension that raises if a resolver
   forgets to call `auth()` or `auth_index()`.
3. **Base policy** — a `Grundit::ApplicationPolicy` with scope-based
   visibility, configurable role defaults, and CRUD stubs.

## Installation

Add to your Gemfile:

```ruby
gem "grundit", git: "https://github.com/Master-Branch-Software/grundit"
```

Then:

```bash
bundle install
```

## Design Philosophy

Grundit operates at the **query and mutation resolver level**, not at the
field level. Every top-level query or mutation resolver calls `auth()` or
`auth_index()` to gate access before returning data.

The **Scope** in a policy defines the universe of records a user is allowed to
see. When `auth()` is called with a single record, the policy constructor runs
that record through the Scope first. If the user cannot see the record, the
policy raises immediately — the action method (`show?`, `update?`, etc.) is
never reached. The Scope acts as a hard visibility boundary, and action methods
only refine permissions within that visible set.

## Quick Start
### 1. Put authorization and enforcement in the right places

Grundit is meant for **top-level query fields and mutations**.

- Include `Grundit::Authorization` in `Types::QueryType` and
  `Mutations::BaseMutation` so query fields and concrete mutations can call
  `auth()` and `auth_index()`
- Put `Grundit::EnforcementExtension` on `QueryType` fields and mutation fields
  so developers cannot forget to authorize

```ruby

# app/graphql/types/query_type.rb
module Types
  class QueryType < Types::BaseObject
    include Grundit::Authorization
    def self.field(*args, authorize: true, **kwargs, &block)
      field_name = args[0]

      super(*args, **kwargs) do
        extension(Grundit::EnforcementExtension,
                  authorize: authorize,
                  field_name: field_name)
        instance_eval(&block) if block
      end
    end

    field :me, UserType, null: false, authorize: false

    def me
      mark_authorized!
      current_user
    end
  end
end

# app/graphql/mutations/base_mutation.rb
module Mutations
  class BaseMutation < GraphQL::Schema::RelayClassicMutation
    include Grundit::Authorization

    def self.field(*args, **kwargs, &block)
      super(*args, **kwargs) do
        extension(Grundit::EnforcementExtension,
                  authorize: true,
                  field_name: args[0])
        instance_eval(&block) if block
      end
    end
  end
end
```

### 2. Write policies

Inherit from `Grundit::ApplicationPolicy`. Define action methods that return
`true` or `false`, and a `Scope` class that filters collections.

```ruby
# app/policies/user_policy.rb
class UserPolicy < Grundit::ApplicationPolicy
  def show?
    user.admin? || record.id == user.id
  end

  def create?
    user.admin?
  end

  def update?
    user.admin? || record.id == user.id
  end

  def destroy?
    user.admin?
  end

  class Scope < Grundit::ApplicationPolicy::Scope
    def resolve
      if user.admin?
        return scope.all
      end

      scope.where(id: user.id)
    end
  end
end
```

### 3. Use `auth()` and `auth_index()` inside query fields

This is the core pattern: declare a field on `QueryType`, then call `auth()` or
`auth_index()` inside that field's resolver method.

```ruby
module Types
  class QueryType < Types::BaseObject
    field :organizations, [OrganizationType], null: false do
      argument :filters, OrganizationFilter, required: true
    end

    def organizations(**params)
      filtered_organizations(params[:filters])
    end

    field :organization, OrganizationType, null: true do
      argument :id, ID, required: true
    end

    def organization(id:)
      auth(Organization.find(id))
    end

    private

    def filtered_organizations(filter)
      auth_index(:organization, Organization.filtered_scope(filter))
    end
  end
end
```

Single-record queries use `auth(...)`. Index queries use `auth_index(...)`.

### 4. Use `auth()` inside mutations

Mutations follow the same idea: inside `resolve`, authorize the target record
or new record before continuing.

```ruby
module Mutations
  class UserUpdate < BaseMutation
    argument :id, ID, required: true
    argument :params, Types::UserUpdateParamsInput, required: true

    field :user, Types::UserType, null: false

    def resolve(id:, params:)
      user = auth(User.find(id), action: :update)
      user.update!(params.to_h)

      { :user => user }
    end
  end
end
```

If a developer forgets to call `auth()` or `auth_index()` in either a query
field or a mutation, the enforcement extension raises immediately.

## Configuration

```ruby
# config/initializers/grundit.rb
Grundit.configure do |config|
  # Roles that pass default_permissions? without any additional_roles.
  # Default: %w[super_admin account_admin organization_admin]
  config.default_permission_roles = %w[super_admin admin]

  # Introspection and Relay fields skipped by the enforcement extension.
  # Default: %w[node nodes __schema __type]
  config.excluded_fields = %w[node nodes __schema __type]
end
```

## Components

### `Grundit::Authorization`

A module usually included in `Types::QueryType` and
`Mutations::BaseMutation` so query fields and concrete mutations can call
`auth()` and `auth_index()` inside their resolver methods. This is intended
for top-level query fields and mutations, not for field-level authorization on
individual type attributes.

| Method | Purpose |
|---|---|
| `auth(object, options = {})` | Authorize a single record. Resolves the policy class, instantiates it, and calls the action method. Returns the object on success, raises `GraphQL::ExecutionError` on failure. |
| `auth_index(policy_class, collection, options = {})` | Authorize a collection. Runs `Policy::Scope#resolve` and returns the scoped result. |
| `mark_authorized!` | Manually flag the current field as authorized (for fields that handle auth outside the normal policy flow). |
| `authorization_called?` | Check whether auth has been called in the current resolution. |
| `current_user` | Reads `context[:current_user]`. |

#### Policy class resolution

The policy class is determined in this order:

1. **Explicit class** — `auth(record, policy_class: UserPolicy)`
2. **Symbol** — `auth(record, policy_class: :user)` → `"UserPolicy".constantize`
3. **Inferred** — `auth(record)` → `"#{record.class.name}Policy".constantize`

#### Passing custom options

Any option key that is not `:current_user`, `:action`, or `:policy_class` is
forwarded to the policy constructor's `options` hash:

```ruby
auth(record, action: :transfer, target_account: other_account)
# => policy.options[:target_account] is available inside the policy
```

### `Grundit::EnforcementExtension`

A `GraphQL::Schema::FieldExtension` intended to be attached to top-level query
fields and mutation fields. It checks `context[:authorization_called]` after
the resolver runs and raises if authorization was not performed. Wire this into
your `QueryType` and `BaseMutation` field overrides to guarantee that no query
field or mutation can return data without calling `auth()` or `auth_index()`
first.

**Options:**

- `:authorize` — `true` (default) or `false` to skip enforcement for a field.
- `:field_name` — used in error messages.
- `:before_resolve` — an optional lambda/proc called before the resolver runs.
  Receives `(context, field_name)`. Raise inside it to block execution.

```ruby
# Example: block all resolvers when password change is required
FORCE_PW_CHECK = ->(context, field_name) {
  if context[:current_user]&.force_password_change?
    raise GraphQL::ExecutionError.new(
      "Password change required.",
      extensions: { "code" => "FORCE_PASSWORD_CHANGE" }
    )
  end
}

extension(Grundit::EnforcementExtension,
          authorize: true,
          field_name: field_name,
          before_resolve: FORCE_PW_CHECK)
```

### `Grundit::ApplicationPolicy`

Base policy class loosely modeled after Pundit.

**Scope** — the most important piece. The Scope defines the universe of
records a user is allowed to see. Subclass `Grundit::ApplicationPolicy::Scope`
and implement `#resolve` to return only the records visible to the given
`user`. This is used by `auth_index()` to filter collections and by the
policy constructor to verify visibility of a single record.

**Constructor** — when a `record` is passed, the constructor runs it through
`Scope#resolve.find(record.id)`. If the record is not in the user's visible
set, an error is raised immediately — the action method (`show?`, `update?`,
etc.) is never reached. The Scope is the first line of defense.

**`default_permissions?`** — checks the user's role against the configured
`default_permission_roles` list. Accepts `:additional_roles` and
`:except_roles` keyword arguments for per-action tuning.

**CRUD stubs** — `show?`, `create?`, `update?`, `destroy?` all delegate to
`default_permissions?`. Override them in your concrete policies. These only
run if the record passes the Scope check first.

### `Grundit::CoreExt::ToBool` (opt-in)

A monkey patch that adds `#to_bool` to `String`, `TrueClass`, `FalseClass`,
and `NilClass`. Useful when boolean values arrive as strings from form posts
or GraphQL variables.

This is **not loaded by default**. Require it explicitly:

```ruby
require "grundit/core_ext/to_bool"

"true".to_bool   # => true
"false".to_bool  # => false
"FALSE".to_bool  # => false
"".to_bool       # => false
true.to_bool     # => true
false.to_bool    # => false
nil.to_bool      # => false
"maybe".to_bool  # => raises ArgumentError
```

## Migration Guide

If you are coming from an app that uses inline `GraphQlAuthorization` and
`ApplicationPolicy` files (as seen in projects like `getmea_server` or
`media_signage`):

### 1. Replace `GraphQlAuthorization`

Delete `app/graphql/graph_ql_authorization.rb`. Add
`include Grundit::Authorization` to `QueryType` and `BaseMutation`:

```ruby
module Types
  class QueryType < Types::BaseObject
    include Grundit::Authorization
  end
end

module Mutations
  class BaseMutation < GraphQL::Schema::RelayClassicMutation
    include Grundit::Authorization
  end
end
```

### 2. Replace `AuthorizationEnforcementExtension`

Delete `app/graphql/authorization_enforcement_extension.rb`. In your
`QueryType` and `BaseMutation` field overrides, replace:

```ruby
extension(AuthorizationEnforcementExtension, ...)
```

with:

```ruby
extension(Grundit::EnforcementExtension, ...)
```

If you used `check_force_password_change: true`, move that logic into a
`:before_resolve` lambda (see the EnforcementExtension section above).

### 3. Update `ApplicationPolicy`

Change `class ApplicationPolicy` to inherit from `Grundit::ApplicationPolicy`:

```ruby
class ApplicationPolicy < Grundit::ApplicationPolicy
end
```

Or, if your policies already inherit from a local `ApplicationPolicy`, update
that base class to inherit from `Grundit::ApplicationPolicy` instead.

### 4. Configure roles

If your app used a different `DEFAULT_PERMISSION_ROLES` list, set it in an
initializer:

```ruby
Grundit.configure do |config|
  config.default_permission_roles = %w[super_admin admin]
end
```

### 5. Optionally load `to_bool`

If you had a `config/initializers/to_bool.rb`, you can replace it with:

```ruby
require "grundit/core_ext/to_bool"
```

## Requirements

- Ruby >= 3.0
- ActiveRecord >= 6.0
- ActiveSupport >= 6.0
- graphql-ruby >= 2.0

## Development

```bash
bundle install
bundle exec rspec
```

## License

MIT — see [LICENSE.txt](LICENSE.txt).

Copyright (c) 2026 MasterBranch Software, LLC — [www.masterbranch.com](https://www.masterbranch.com)
