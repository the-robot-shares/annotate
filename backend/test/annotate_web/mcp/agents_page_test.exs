defmodule AnnotateWeb.MCP.AgentsPageTest do
  @moduledoc "/dashboard/agents: render, connected-client list (granted scopes), revoke kills the token, activity log."
  use AnnotateWeb.ConnCase, async: false

  import AnnotateWeb.DashboardCase
  import AnnotateWeb.MCPCase

  alias AnnotateWeb.Hologram.Pages.DashboardAgentsPage

  test "renders the connect snippets with the MCP URL; signed-out users are sent to sign in" do
    conn = signed_in_conn(801)
    html = conn |> recycle() |> get("/dashboard/agents") |> html_response(200)
    assert html =~ "claude mcp add --transport http annotate " <> resource()
    assert html =~ "Connected clients"
    assert html =~ "dsh-nav-agents"
    assert html =~ "Cursor opens the sign-in"
    refute html =~ "Not yet supported"

    anon = get(build_conn(), "/dashboard/agents")
    assert anon.status in [302, 200]
    refute anon.resp_body =~ "claude mcp add"
  end

  test "lists a connected client with its granted scopes; revoke kills its live token" do
    %{user: user, server: server} = gh_user!(802)

    %{token: token, client_id: client_id} =
      mint_token(user.id, ["comments:read", "comments:write"], "Claude <b>Code</b>")

    assert mcp_post(token, init_body()).status == 200

    {:loaded, %{clients: [c], activity: _}} =
      run_command(DashboardAgentsPage, :load_agents, %{}, server)

    assert c.client_id == client_id
    assert c.name == "Claude <b>Code</b>"
    assert Enum.sort(c.scopes) == ["comments:read", "comments:write"]

    {:revoked, %{clients: []}} =
      run_command(DashboardAgentsPage, :revoke, %{client_id: client_id}, server)

    assert mcp_post(token, init_body()).status == 401
  end

  test "revoking another user's client changes nothing for them" do
    %{user: alice} = gh_user!(803)
    %{server: mallory} = gh_user!(804)
    %{token: token, client_id: client_id} = mint_token(alice.id)
    run_command(DashboardAgentsPage, :revoke, %{client_id: client_id}, mallory)
    assert mcp_post(token, init_body()).status == 200
  end

  test "a pending (gated) user gets no data" do
    %{server: server} = gh_user!(805, %{pending: true})
    {:failed, %{error: _}} = run_command(DashboardAgentsPage, :load_agents, %{}, server)
  end

  test "activity shows audited writes/denials" do
    %{user: user, server: server} = gh_user!(806)
    %{token: token} = mint_token(user.id)
    sid = mcp_session!(token)
    {:error, _} = call_tool(token, sid, "get_thread", %{thread_id: Ecto.UUID.generate()})
    {:loaded, %{activity: [a | _]}} = run_command(DashboardAgentsPage, :load_agents, %{}, server)
    assert a.tool == "get_thread"
    assert a.outcome == "denied"
  end

  defp init_body,
    do: %{
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: %{
        protocolVersion: "2025-11-25",
        capabilities: %{},
        clientInfo: %{name: "t", version: "0"}
      }
    }
end
