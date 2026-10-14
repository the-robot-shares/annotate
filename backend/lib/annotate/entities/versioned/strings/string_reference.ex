defmodule Annotate.Versioned.Strings.StringReference do
  use Noizu.Entity.ReferenceBehaviour,
    identifier_type: :uuid,
    entity: Annotate.Versioned.Strings.String
end
