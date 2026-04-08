# Grundit

A Pundit-compatible, GraphQL-centric authorization framework for Rails.

Grundit gives you four things:

1. **`GrunditQuery`** — a GraphQL query base class with authorization and
   enforcement already wired in
2. **`GrunditMutation`** — a GraphQL mutation base class with authorization and
   enforcement already wired in
3. **`auth()` / `auth_index()`** — authorize single objects or collections
   from top-level query fields and mutations using Pundit-style policy classes
4. **Base policy** — a `Grundit::ApplicationPolicy` with scope-based
   visibility, configurable role defaults, and CRUD stubs

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
### 1. Derive from `GrunditQuery` and `GrunditMutation`

Grundit is meant for **top-level query fields and mutations**.

- `GrunditQuery` gives `QueryType` both authorization and enforcement
- `GrunditMutation` gives your mutation base class both authorization and
  enforcement
- Using Grundit should be a simple insertion of these classes in your
  inheritance hierarchy

```ruby

# app/graphql/types/query_type.rb
module Types
  class QueryType < GrunditQuery
    field_class Types::BaseField
    connection_type_class Types::BaseConnection
    edge_type_class Types::BaseEdge

    field :me, UserType, null: false, authorize: false

    def me
      mark_authorized!
      current_user
    end
  end
end

# app/graphql/mutations/base_mutation.rb
module Mutations
  class BaseMutation < GrunditMutation
    argument_class Types::BaseArgument
    field_class Types::BaseField
    input_object_class Types::BaseInputObject
    object_class Types::BaseObject
  end
end
```

### 1b. Typical Rails app setup

Many Rails GraphQL apps already have application-level base classes for queries
and mutations. In that case, insert Grundit once in that inheritance chain and
keep the rest of your app inheriting normally.

```ruby
# app/graphql/application_query.rb
class ApplicationQuery < GrunditQuery
  field_class Types::BaseField
  connection_type_class Types::BaseConnection
  edge_type_class Types::BaseEdge
end

# app/graphql/application_mutation.rb
class ApplicationMutation < GrunditMutation
  argument_class Types::BaseArgument
  field_class Types::BaseField
  input_object_class Types::BaseInputObject
  object_class Types::BaseObject
end

# app/graphql/types/query_type.rb
module Types
  class QueryType < ApplicationQuery
  end
end

# app/graphql/mutations/user_update.rb
module Mutations
  class UserUpdate < ApplicationMutation
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
  class QueryType < GrunditQuery
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

### 5. Pass custom context into a policy when needed

Any option you pass to `auth(...)` other than `:current_user`, `:action`, and
`:policy_class` is forwarded to the policy constructor in `options`. This is
useful when the policy needs extra context beyond the user and record.

```ruby
def move_project(id:, destination_account_id:)
  destination_account = Account.find(destination_account_id)
  project = auth(Project.find(id),
                 action: :move,
                 destination_account: destination_account)

  project.move_to!(destination_account)
  { :project => project }
end

class ProjectPolicy < Grundit::ApplicationPolicy
  def move?
    user.admin? && options[:destination_account].present?
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

### `GrunditQuery`

A query base class for top-level GraphQL query fields. It:

- inherits from `GraphQL::Schema::Object`
- includes `Grundit::Authorization`
- wires `Grundit::EnforcementExtension` into `field(...)`

Use it as the parent class for your app's `QueryType`.

### `GrunditMutation`

A mutation base class for top-level GraphQL mutations. It:

- inherits from `GraphQL::Schema::RelayClassicMutation`
- includes `Grundit::Authorization`
- wires `Grundit::EnforcementExtension` into `field(...)`

Use it as the parent class for your app's mutation base class.

### `Grundit::Authorization`

The authorization API used by `GrunditQuery` and `GrunditMutation`. If you are
using those base classes, you usually do not need to include this module
yourself. This is intended for top-level query fields and mutations, not for
field-level authorization on individual type attributes.

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

A `GraphQL::Schema::FieldExtension` used internally by `GrunditQuery` and
`GrunditMutation`. It checks `context[:authorization_called]` after the
resolver runs and raises if authorization was not performed. You normally do
not need to attach it manually unless you are building your own base classes.

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
