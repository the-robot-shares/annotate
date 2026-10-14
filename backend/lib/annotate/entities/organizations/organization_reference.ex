defmodule Annotate.Organizations.OrganizationReference do
  use Noizu.Entity.ReferenceBehaviour,
    identifier_type: :uuid,
    entity: Annotate.Organizations.Organization
end
