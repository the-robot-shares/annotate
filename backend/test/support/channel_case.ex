defmodule AnnotateWeb.ChannelCase do
  @moduledoc """
  ExUnit case template for annotate channel/socket tests.

  Sandboxed Repo (same as the controller cases) plus the annotate API
  fixtures from `AnnotateWeb.AnnotateAPICase` (site/commenter/token/thread
  helpers), so channel tests build the same world the REST tests do.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto.Query
      import Phoenix.ChannelTest
      import Annotate.DataCase
      import AnnotateWeb.AnnotateAPICase

      @endpoint AnnotateWeb.Endpoint
    end
  end

  setup tags do
    Annotate.DataCase.setup_sandbox(tags)
    :ok
  end
end
