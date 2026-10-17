defmodule AnnotateWeb.MCP.WriteToolsTest do
  @moduledoc """
  MCP write surface: reply / resolve / reopen / delete through the same
  Comments context as the dashboard inbox (realtime fan-out included), role
  and scope gates, every write + denial audited (no bodies in the audit
  row), and the per-(user, client) write rate limit.
  """
  use AnnotateWeb.ConnCase, async: false

  import AnnotateWeb.DashboardCase
  import AnnotateWeb.MCPCase
  import Ecto.Query

  alias Annotate.Comments
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.Comment
  alias Annotate.Schema.Annotate.Commenter
  alias Annotate.Schema.Annotate.Thread
  alias Annotate.SiteMembers
  alias Annotate.Sites

  setup do
    owner = gh_user!(60, %{name: "Olive Owner"})
    admin = gh_user!(61)
    member = gh_user!(62, %{name: "Mel Member"})
    stranger = gh_user!(63)

    {:ok, site, _} =
      Sites.create_site_with_owner(
        %{"slug" => "w-site", "name" => "W", "allowed_origins" => ["https://w.example"]},
        Repo.reload!(owner.user)
      )

    {:ok, _} = SiteMembers.add_member(site, Repo.reload!(admin.user), :admin)
    {:ok, _} = SiteMembers.add_member(site, Repo.reload!(member.user), :member)

    visitor = Repo.insert!(%Commenter{authentik_sub: "ak-w-visitor", display_name: "Vera"})

    {:ok, thread} =
      Comments.create_thread(site, visitor, %{
        "page_key" => "/",
        "url" => "https://w.example/",
        "body_md" => "Please fix the header",
        "anchor" => %{"css" => "#h"}
      })

    [visitor_comment] = thread.comments

    %{
      site: site,
      owner: owner,
      admin: admin,
      member: member,
      stranger: stranger,
      thread: thread,
      visitor_comment: visitor_comment
    }
  end

  defp session(user, scopes \\ Annotate.MCP.Config.scopes()) do
    %{token: token, client_id: client_id} = mint_token(user.id, scopes)
    {token, mcp_session!(token), client_id}
  end

  defp audit_rows(user_id) do
    Repo.all(
      from(a in "mcp_audit_events",
        where: a.user_id == type(^user_id, :binary_id),
        order_by: [asc: a.inserted_at],
        select: %{
          tool: a.tool,
          outcome: a.outcome,
          reason: a.reason,
          site_slug: a.site_slug,
          args_hash: a.args_hash,
          client_id: a.client_id
        }
      )
    )
  end

  test "reply → team comment, realtime inbox ping, audit row without the body", %{
    member: m,
    thread: t,
    site: site
  } do
    {token, sid, client_id} = session(m.user)
    AnnotateWeb.Endpoint.subscribe(Annotate.Realtime.page_topic(site, "/"))

    assert {:ok, %{"comment" => c, "posted_as" => "site team"}} =
             call_tool(token, sid, "reply_to_thread", %{
               thread_id: t.id,
               body: "  On it — fixed in the next deploy  "
             })

    assert c["team"] == true
    assert_receive %Phoenix.Socket.Broadcast{event: "comment_created"}, 1_000
    assert c["untrusted"]["body"] == "On it — fixed in the next deploy"
    stored = Repo.get!(Comment, c["id"]) |> Repo.preload(:author)
    assert stored.author.user_id == m.user.id
    assert stored.author.site_id == site.id

    assert [
             %{
               tool: "reply_to_thread",
               outcome: "ok",
               site_slug: "w-site",
               client_id: ^client_id,
               args_hash: hash
             }
           ] =
             audit_rows(m.user.id)

    assert String.length(hash) == 64

    raw =
      Repo.query!("SELECT row_to_json(a)::text FROM mcp_audit_events a").rows
      |> List.flatten()
      |> Enum.join()

    refute raw =~ "fixed in the next deploy"
  end

  test "reply validates body and parent", %{member: m, thread: t} do
    {token, sid, _} = session(m.user)

    assert {:error, msg} =
             call_tool(token, sid, "reply_to_thread", %{thread_id: t.id, body: "   "})

    assert msg =~ "invalid_body"

    assert {:error, msg} =
             call_tool(token, sid, "reply_to_thread", %{
               thread_id: t.id,
               body: "x",
               parent_id: Ecto.UUID.generate()
             })

    assert msg =~ "invalid_parent"

    assert {:error, _} =
             call_tool(token, sid, "reply_to_thread", %{
               thread_id: t.id,
               body: String.duplicate("a", 10_001)
             })

    assert Enum.all?(audit_rows(m.user.id), &(&1.outcome == "error"))
  end

  test "resolve then reopen (member), state visible to the dashboard", %{member: m, thread: t} do
    {token, sid, _} = session(m.user)

    assert {:ok, %{"status" => "resolved"}} =
             call_tool(token, sid, "resolve_thread", %{thread_id: t.id})

    assert %Thread{status: :resolved, resolved_by: by} = Repo.get!(Thread, t.id)
    assert Repo.get!(Commenter, by).user_id == m.user.id

    assert {:ok, %{"status" => "open"}} =
             call_tool(token, sid, "reopen_thread", %{thread_id: t.id})

    assert %Thread{status: :open} = Repo.get!(Thread, t.id)
    assert ["resolve_thread", "reopen_thread"] == Enum.map(audit_rows(m.user.id), & &1.tool)
  end

  test "non-member writes are not_found and change nothing", %{
    stranger: s,
    thread: t,
    visitor_comment: vc
  } do
    {token, sid, _} = session(s.user)
    assert {:error, m1} = call_tool(token, sid, "reply_to_thread", %{thread_id: t.id, body: "hi"})
    assert {:error, m2} = call_tool(token, sid, "resolve_thread", %{thread_id: t.id})
    assert {:error, m3} = call_tool(token, sid, "delete_comment", %{comment_id: vc.id})

    assert {:error, m4} =
             call_tool(token, sid, "delete_comment", %{comment_id: Ecto.UUID.generate()})

    assert Enum.all?([m1, m2, m3], &(&1 =~ "not_found"))
    assert m3 == m4
    assert Repo.get!(Thread, t.id).status == :open
    assert Repo.get!(Comment, vc.id).deleted_at == nil

    assert Enum.all?(
             audit_rows(s.user.id),
             &(&1.outcome == "denied" and &1.reason == "not_found")
           )
  end

  test "delete: member may delete only own team replies; admin anyone's", %{
    member: m,
    admin: a,
    thread: t,
    visitor_comment: vc
  } do
    {mtoken, msid, _} = session(m.user)

    {:ok, %{"comment" => %{"id" => own}}} =
      call_tool(mtoken, msid, "reply_to_thread", %{thread_id: t.id, body: "mine"})

    assert {:error, msg} = call_tool(mtoken, msid, "delete_comment", %{comment_id: vc.id})
    assert msg =~ "forbidden"
    assert Repo.get!(Comment, vc.id).deleted_at == nil

    assert {:ok, %{"deleted" => true}} =
             call_tool(mtoken, msid, "delete_comment", %{comment_id: own})

    {atoken, asid, _} = session(a.user)

    assert {:ok, %{"deleted" => true}} =
             call_tool(atoken, asid, "delete_comment", %{comment_id: vc.id})

    refute is_nil(Repo.get!(Comment, vc.id).deleted_at)

    # Already deleted → not_found (no double delete).
    assert {:error, gone} = call_tool(atoken, asid, "delete_comment", %{comment_id: vc.id})
    assert gone =~ "not_found"

    outcomes = Enum.map(audit_rows(m.user.id), &{&1.tool, &1.outcome, &1.reason})
    assert {"delete_comment", "error", "forbidden"} in outcomes
    assert {"delete_comment", "ok", nil} in outcomes
  end

  test "a demoted admin loses moderation on the next call", %{
    admin: a,
    site: site,
    visitor_comment: vc
  } do
    {token, sid, _} = session(a.user)
    {:ok, _} = SiteMembers.update_role(site, a.user.id, :member)
    assert {:error, msg} = call_tool(token, sid, "delete_comment", %{comment_id: vc.id})
    assert msg =~ "forbidden"
  end

  test "scope gate inside the tool too (defence in depth)", %{member: m, thread: t} do
    %{token: token} = mint_token(m.user.id, ["comments:read"])
    # The HTTP layer already answers 403 for a write tool…
    sid = mcp_session!(token)

    conn =
      mcp_post(
        token,
        %{
          jsonrpc: "2.0",
          id: 1,
          method: "tools/call",
          params: %{name: "resolve_thread", arguments: %{thread_id: t.id}}
        },
        sid
      )

    assert conn.status == 403
    # …and the tool itself refuses a caller without the scope.
    caller_ctx = %Noizu.MCP.Ctx{
      auth: %Noizu.MCP.Auth.Principal{
        subject: m.user.id,
        authenticator: :test,
        claims: peek_claims(token)
      }
    }

    assert {:error, msg} = Annotate.MCP.Tools.ResolveThread.call(%{thread_id: t.id}, caller_ctx)
    assert msg =~ "insufficient_scope"
    assert Repo.get!(Thread, t.id).status == :open
  end

  test "write rate limit: 30 per minute per (user, client), then rate_limited (audited)", %{
    member: m,
    thread: t
  } do
    {token, sid, _} = session(m.user)

    for _ <- 1..30 do
      assert {:ok, _} = call_tool(token, sid, "resolve_thread", %{thread_id: t.id})
    end

    assert {:error, msg} = call_tool(token, sid, "resolve_thread", %{thread_id: t.id})
    assert msg =~ "rate_limited"
    assert %{outcome: "denied", reason: "rate_limited"} = List.last(audit_rows(m.user.id))

    # A different client of the same user has its own bucket; reads are separate.
    {token2, sid2, _} = session(m.user)
    assert {:ok, _} = call_tool(token2, sid2, "resolve_thread", %{thread_id: t.id})
    assert {:ok, _} = call_tool(token, sid, "list_sites", %{})
  end

  test "read rate limit: 120 per minute", %{member: m} do
    {token, sid, _} = session(m.user)
    for _ <- 1..120, do: assert({:ok, _} = call_tool(token, sid, "list_sites", %{}))
    assert {:error, msg} = call_tool(token, sid, "list_sites", %{})
    assert msg =~ "rate_limited"
  end

  test "tools/list marks delete destructive", %{member: m} do
    {token, sid, _} = session(m.user)

    body =
      rpc_body(mcp_post(token, %{jsonrpc: "2.0", id: 2, method: "tools/list", params: %{}}, sid))

    tools = Map.new(body["result"]["tools"], &{&1["name"], &1})
    assert tools["delete_comment"]["annotations"]["destructiveHint"] == true
    assert tools["reply_to_thread"]["annotations"]["readOnlyHint"] == false
    assert map_size(tools) == 8
  end
end
