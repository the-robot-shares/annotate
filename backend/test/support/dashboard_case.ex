defmodule AnnotateWeb.DashboardCase do
  @moduledoc """
  Dashboard (Hologram) test helpers: GitHub-signed-in users as a Hologram
  server struct (for direct page/command calls) and as a recycled Plug conn
  (for full HTTP renders).
  """

  @doc "Signs a GitHub profile in → `%{user, server, token}`."
  def gh_user!(n, attrs \\ %{}) do
    profile =
      Map.merge(
        %{
          github_id: 50_000 + n,
          login: "gh#{n}",
          email: "gh#{n}@example.com",
          name: "GH #{n}",
          avatar_url: nil
        },
        attrs
      )

    {:ok, %{user: user, session: session}} = Annotate.Dashboard.GithubLogin.sign_in(profile)

    # The dashboard is invite-only; these helpers model INVITED (active)
    # owners unless `pending: true` is passed in attrs.
    user =
      if Map.get(attrs, :pending) do
        user
      else
        user
        |> Ecto.Changeset.change(status: :active, approved_at: DateTime.utc_now())
        |> Annotate.Repo.update!()
      end

    {:ok, token, _} =
      Annotate.Guardian.encode_and_sign(session, %{}, token_type: "access", ttl: {1, :hour})

    %{user: user, token: token, server: %Hologram.Server{session: %{"access_token" => token}}}
  end

  @doc "Runs a page command and returns `{action_name, params}` of the reply."
  def run_command(page, name, params, server) do
    %Hologram.Server{next_action: %{name: action, params: reply}} =
      page.command(name, params, server)

    {action, reply}
  end

  @doc "Full HTTP sign-in through the GitHub stub; returns a conn carrying the session cookies."
  def signed_in_conn(n) do
    import Phoenix.ConnTest

    q =
      URI.encode_query(%{
        stub_id: 70_000 + n,
        stub_login: "h#{n}",
        stub_email: "h#{n}@example.com"
      })

    conn = dispatch(build_conn(), AnnotateWeb.Endpoint, :get, "/auth/github?" <> q, nil)
    conn = conn |> recycle() |> dispatch(AnnotateWeb.Endpoint, :get, redirected_to(conn), nil)

    # Invite-only dashboard: model an invited (active) owner.
    import Ecto.Query

    Annotate.Repo.update_all(
      from(u in Annotate.Schema.Users.User, where: u.email == ^"h#{n}@example.com"),
      set: [status: :active, approved_at: DateTime.utc_now()]
    )

    conn |> recycle() |> dispatch(AnnotateWeb.Endpoint, :get, redirected_to(conn), nil)
  end
end
