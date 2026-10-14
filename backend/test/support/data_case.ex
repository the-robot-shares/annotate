defmodule Annotate.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Annotate.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Annotate.DataCase
    end
  end

  setup tags do
    Annotate.DataCase.setup_sandbox(tags)
    :ok
  end

  # <REMOVED UUID HERE> setup_sandbox :: auto-generated pointer for public function setup_sandbox
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Annotate.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end
end
