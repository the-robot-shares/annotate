defmodule Annotate.Authz.Groups.GroupReference do
  use Noizu.Entity.ReferenceBehaviour,
    identifier_type: :uuid,
    entity: Annotate.Authz.Groups.Group
end
