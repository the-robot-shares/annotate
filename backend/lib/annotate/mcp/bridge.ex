defmodule Annotate.MCP.Bridge do
  @moduledoc """
  `Upstream.HostSession` callbacks: who is the human at `/oauth/authorize`?

  The answer is the **dashboard** session — the Guardian access token the
  Hologram sign-in stores in the `_annotate_key` cookie — and nothing else.
  A subject is returned only for a user that is not deleted, not disabled,
  and passes the invite gate (`Annotate.Dashboard.Access.allowed?/1`). A
  signed-in but gated account gets an error page, never a consent screen and
  never a login loop. Embed (widget) identities are a different realm and can
  never become an MCP subject.
  """

  alias Annotate.Guardian

  @doc "`{:ok, user_id} | :none | {:error, reason}`"
  def current_subject(conn) do
    conn = Plug.Conn.fetch_session(conn)

    with token when is_binary(token) <- Plug.Conn.get_session(conn, "access_token"),
         {:ok, claims} <- Guardian.decode_and_verify(token, %{"typ" => "access"}),
         {:ok, session} <- Guardian.resource_from_claims(claims),
         %{id: user_id} = user when is_binary(user_id) <- session_user(session) do
      if Annotate.MCP.Authz.user_allowed?(user),
        do: {:ok, user_id},
        else: {:error, :access_denied}
    else
      _ -> :none
    end
  end

  @doc "Where a signed-out user goes; `return_to` is same-origin by construction."
  def login_url(_conn, return_to), do: "/sign-in?return_to=" <> URI.encode_www_form(return_to)

  # Re-read the users row (status/deleted_at as of now), never the entity
  # cached in the session.
  defp session_user(%Annotate.Users.Sessions.UserSession{user: user}) do
    id =
      case user do
        {:ref, _, id} -> id
        %{id: id} -> id
        _ -> nil
      end

    if is_binary(id), do: Annotate.Repo.get(Annotate.Schema.Users.User, id)
  end

  defp session_user(_), do: nil
end
