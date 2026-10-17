defmodule AnnotateWeb.AnnotateAPI.RateLimitTest do
  use AnnotateWeb.AnnotateAPICase, async: true

  alias AnnotateWeb.Plugs.RateLimit

  # Unique site slugs give each test its own Hammer bucket
  # ("annotate_write:<ip>:<site>"), so tests never contend.

  defp post_conn(site_slug) do
    build_conn()
    |> Map.put(:method, "POST")
    |> Map.put(:params, %{"site" => site_slug})
    |> Map.put(:path_info, ["api", "v1", "sites", site_slug, "threads"])
  end

  defp run(conn, state), do: RateLimit.call(conn, state)

  describe "annotate_write action" do
    test "init marks the action writes-only with a 60/min budget" do
      state = RateLimit.init(action: :annotate_write)
      assert state.writes_only
      assert state.limit == 60
      assert state.period == 60_000
    end

    test "writes under the limit pass through unchanged", %{conn: _conn} do
      {site, _key} = create_site()
      state = RateLimit.init(action: :annotate_write)
      conn = run(post_conn(site.slug), state)
      refute conn.halted
      assert conn.status == nil
    end

    test "exhausting the (ip, site) bucket denies the next write with 429", %{conn: _conn} do
      {site, _key} = create_site()
      state = RateLimit.init(action: :annotate_write)
      conn = post_conn(site.slug)

      for _ <- 1..state.limit, do: run(conn, state)

      denied = run(conn, state)
      assert denied.halted
      assert denied.status == 429
      assert get_resp_header(denied, "retry-after") == ["60"]
      assert Jason.decode!(denied.resp_body)["error"] =~ "Too many requests"
    end

    test "buckets are per (ip, site): another site still allowed", %{conn: _conn} do
      {site, _key} = create_site()
      {other_site, _key} = create_site()
      state = RateLimit.init(action: :annotate_write)
      conn = post_conn(site.slug)

      for _ <- 1..state.limit, do: run(conn, state)
      assert run(conn, state).halted

      fresh = run(post_conn(other_site.slug), state)
      refute fresh.halted
    end

    test "reads are never counted (writes-only action)", %{conn: _conn} do
      {site, _key} = create_site()
      state = RateLimit.init(action: :annotate_write)

      exhausted = post_conn(site.slug)
      for _ <- 1..state.limit, do: run(exhausted, state)

      get_conn =
        build_conn()
        |> Map.put(:method, "GET")
        |> Map.put(:params, %{"site" => site.slug})

      conn = run(get_conn, state)
      refute conn.halted
    end
  end

  describe "auth actions keep working" do
    test "auth action still rate-limits per ip" do
      state = RateLimit.init(action: :auth)
      assert state.limit == 10

      # one dedicated ip for this test (unroutable test range, unique per run)
      ip = {10, Enum.random(20..250), Enum.random(1..250), 4}

      conn =
        build_conn()
        |> Map.put(:method, "POST")
        |> Map.put(:params, %{})
        |> Map.put(:remote_ip, ip)

      for _ <- 1..state.limit, do: run(conn, state)

      denied = run(conn, state)
      assert denied.halted
      assert denied.status == 429
    end
  end

  describe "spoofing resistance" do
    defp xff_conn(site_slug, xff, remote_ip \\ {127, 0, 0, 1}) do
      post_conn(site_slug)
      |> Map.put(:remote_ip, remote_ip)
      |> put_req_header("x-forwarded-for", xff)
    end

    test "client_ip uses the rightmost trusted hop, ignoring forged left entries" do
      conn = xff_conn("s", "6.6.6.6, 7.7.7.7, 10.1.2.3")
      assert RateLimit.client_ip(conn) == "10.1.2.3"
      assert RateLimit.client_ip(xff_conn("s", "9.9.9.9, 10.1.2.3")) == "10.1.2.3"
    end

    test "unparsable / absent XFF falls back to the socket peer" do
      assert RateLimit.client_ip(xff_conn("s", "not-an-ip", {10, 9, 8, 7})) == "10.9.8.7"
      conn = build_conn() |> Map.put(:remote_ip, {10, 9, 8, 7})
      assert RateLimit.client_ip(conn) == "10.9.8.7"
    end

    test "hops = 0 ignores XFF entirely" do
      Application.put_env(:annotate, :rate_limit_trusted_hops, 0)
      on_exit(fn -> Application.delete_env(:annotate, :rate_limit_trusted_hops) end)
      assert RateLimit.client_ip(xff_conn("s", "1.2.3.4", {10, 9, 8, 7})) == "10.9.8.7"
    end

    test "rotating a forged left XFF entry does not escape the bucket" do
      {site, _key} = create_site()
      state = RateLimit.init(action: :annotate_write)
      real = "10.#{Enum.random(1..250)}.#{Enum.random(1..250)}.9"

      for i <- 1..state.limit,
          do: run(xff_conn(site.slug, "66.66.66.#{rem(i, 250)}, #{real}"), state)

      denied = run(xff_conn(site.slug, "77.77.77.77, #{real}"), state)
      assert denied.halted
      assert denied.status == 429
    end

    test "unknown site keys share a single bucket" do
      state = RateLimit.init(action: :annotate_write)
      real = "10.#{Enum.random(1..250)}.#{Enum.random(1..250)}.8"

      for i <- 1..state.limit,
          do:
            run(xff_conn("no-such-site-#{i}-#{System.unique_integer([:positive])}", real), state)

      denied =
        run(xff_conn("yet-another-bogus-#{System.unique_integer([:positive])}", real), state)

      assert denied.halted
      assert denied.status == 429
    end
  end
end
