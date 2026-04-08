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

### 1. Include the authorization module

Mix `Grundit::Authorization` into your base GraphQL classes. This gives every
query and mutation resolver access to `auth()`, `auth_index()`,
`mark_authorized!`, and `current_user`.

```ruby
# app/graphql/types/base_object.rb
module Types
  class BaseObject < GraphQL::Schema::Object
    include Grundit::Authorization
  end
end

# app/graphql/mutations/base_mutation.rb
module Mutations
  class BaseMutation < GraphQL::Schema::RelayClassicMutation
    include Grundit::Authorization
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

### 3. Authorize in resolvers

```ruby
# Single object — looks up UserPolicy, calls #show? by default
def user(id:)
  auth(User.find(id))
end

# Single object with explicit action
def update_user(id:, params:)
  user = auth(User.find(id), action: :update)
  user.update!(params)
  user
end

# Collection — runs UserPolicy::Scope#resolve
def users
  auth_index(:user, User.all)
end
```

### 4. Enforce authorization (optional but recommended)

Wire up `Grundit::EnforcementExtension` so that any resolver that forgets to
call `auth()` or `auth_index()` raises an error instead of silently leaking
data.

```ruby
# app/graphql/types/query_type.rb
module Types
  class QueryType < Types::BaseObject
    def self.field(*args, authorize: true, **kwargs, &block)
      field_name = args[0]

      super(*args, **kwargs) do
        extension(Grundit::EnforcementExtension,
                  authorize: authorize,
                  field_name: field_name)
        instance_eval(&block) if block
      end
    end

    # Fields that handle auth manually can opt out:
    field :public_status, String, null: false, authorize: false

    def public_status
      "ok"
    end
  end
end
```

The same pattern works for mutations:

```ruby
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

A module you include in your base GraphQL classes (BaseObject, BaseMutation).
It provides resolver-level authorization — call `auth()` or `auth_index()` in
your query and mutation resolvers to gate access through policy classes. This
is not intended for field-level authorization on individual type attributes.

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

A `GraphQL::Schema::FieldExtension` that checks `context[:authorization_called]`
after every query or mutation resolver and raises if authorization was not
performed. Wire this into your `QueryType` and `BaseMutation` field overrides
to guarantee that no resolver can return data without calling `auth()` or
`auth_index()` first.

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

Delete `app/graphql/graph_ql_authorization.rb`. Change every `include
GraphQlAuthorization` to:

```ruby
include Grundit::Authorization
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
