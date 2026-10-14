defmodule Annotate.Authz.ScopedMemberships.ScopedMembershipReference do
  use Noizu.Entity.ReferenceBehaviour,
    identifier_type: :uuid,
    entity: Annotate.Authz.ScopedMemberships.ScopedMembership
end
