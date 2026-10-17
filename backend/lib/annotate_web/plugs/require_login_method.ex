defmodule AnnotateWeb.Plugs.RequireLoginMethod do
  @moduledoc """
  404s a route whose sign-in method is disabled (`Annotate.Auth.LoginMethods`).

      plug AnnotateWeb.Plugs.RequireLoginMethod, method: "password"
      plug AnnotateWeb.Plugs.RequireLoginMethod, from_param: "provider"

  404 (not 403) so a GitHub-only deployment looks like it never had the route.
  """

  @behaviour Plug
  import Plug.Conn

  alias Annotate.Auth.LoginMethods

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    method =
      case Keyword.fetch(opts, :from_param) do
        {:ok, param} -> conn.path_params[param] || conn.params[param]
        :error -> Keyword.fetch!(opts, :method)
      end

    if is_binary(method) and LoginMethods.enabled?(method) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, ~s({"error":"not_found"}))
      |> halt()
    end
  end
end
