defmodule AnnotateWeb.Plugs.DashboardSession do
  @moduledoc """
  Resolves the dashboard user for plain Phoenix routes served next to the
  Hologram dashboard. The dashboard signs in through Hologram pages, which
  keep Guardian tokens in the shared cookie session (`_annotate_key`) — this
  plug verifies the same `:access_token` and assigns `:dashboard_user`
  (nil when absent/expired; the controller decides the redirect).

  NOT a gate by itself: assigning nil on failure lets each route choose
  between redirecting to /sign-in and answering 404.
  """

  @behaviour Plug

  import Plug.Conn, only: [get_session: 2, assign: 3]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    user =
      case get_session(conn, :access_token) do
        token when is_binary(token) ->
          case Annotate.Hologram.Auth.user_from_access_token(token) do
            {:ok, user} -> user
            _ -> nil
          end

        _ ->
          nil
      end

    assign(conn, :dashboard_user, user)
  end
end
