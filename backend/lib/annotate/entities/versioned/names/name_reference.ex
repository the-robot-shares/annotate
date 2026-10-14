defmodule Annotate.Versioned.Names.NameReference do
  use Noizu.Entity.ReferenceBehaviour,
    identifier_type: :uuid,
    entity: Annotate.Versioned.Names.Name
end
