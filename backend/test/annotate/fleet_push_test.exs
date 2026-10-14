defmodule Annotate.FleetPushTest do
  @moduledoc """
  FleetPush: no-op without a key, payload shape (nils from the default
  provider), status handling, Oban wiring, and — critically — a test that
  drives the REAL default HTTP client (a stubbed-everything suite once shipped
  a broken default client module name to prod). Application env is mutated per
  test, so this file is async: false.
  """

  use Annotate.DataCase

  alias Annotate.Schema.Users.Sessions.UserSession
  alias Annotate.Schema.Users.User
  alias Annotate.FleetPush

  import ExUnit.CaptureLog

  @calls_key {__MODULE__, :calls}
  @reply_key {__MODULE__, :reply}
  @base_cfg_key {__MODULE__, :base_cfg}

  setup do
    :persistent_term.put(@calls_key, [])

    # Preserve the compile-time base config (config.exs) — the real-default-
    # client test must exercise exactly the client the SHIPPED config selects,
    # and the wiring test must see the shipped provider, so merge the stub in
    # instead of replacing the keyword list.
    base = Application.get_env(:annotate, FleetPush, [])
    :persistent_term.put(@base_cfg_key, base)

    Application.put_env(
      :annotate,
      FleetPush,
      Keyword.put(base, :http_client, __MODULE__.StubClient)
    )

    :persistent_term.put(@reply_key, {:ok, 200, "{}"})

    on_exit(fn ->
      :persistent_term.erase(@calls_key)
      :persistent_term.erase(@reply_key)
      :persistent_term.erase(@base_cfg_key)

      # Restore the test's captured base so the next setup captures the
      # shipped config, never a prior test's with_key leftover.
      if base == [] do
        Application.delete_env(:annotate, FleetPush)
      else
        Application.put_env(:annotate, FleetPush, base)
      end
    end)

    :ok
  end

  defp base_cfg, do: :persistent_term.get(@base_cfg_key, [])

  defmodule StubClient do
    @moduledoc false
    @behaviour Annotate.FleetPush.Client

    @impl true
    def post(url, headers, body) do
      key = {Annotate.FleetPushTest, :calls}

      :persistent_term.put(key, [{url, headers, body} | :persistent_term.get(key, [])])
      :persistent_term.get({Annotate.FleetPushTest, :reply}, {:ok, 200, "{}"})
    end
  end

  defp calls, do: :persistent_term.get(@calls_key, [])
  defp set_reply(reply), do: :persistent_term.put(@reply_key, reply)

  defp with_key(key, url \\ "http://fleet.test/ingest") do
    Application.put_env(:annotate, FleetPush,
      key: key,
      url: url,
      http_client: __MODULE__.StubClient
    )
  end

  defp user!(attrs \\ %{}) do
    Repo.insert!(
      struct(
        User,
        Map.merge(%{email: "u#{System.unique_integer()}@test", status: :active}, attrs)
      )
    )
  end

  defp session!(user_id, attrs \\ %{}) do
    Repo.insert!(struct(UserSession, Map.merge(%{user_id: user_id, status: :active}, attrs)))
  end

  describe "perform/1" do
    test "no-ops with no key configured" do
      assert :ok = FleetPush.perform(%Oban.Job{args: %{}})
      assert calls() == []
    end

    test "no-ops with a blank key configured" do
      with_key("")

      assert :ok = FleetPush.perform(%Oban.Job{args: %{}})
      assert calls() == []
    end

    test "default provider pushes nils (born-instrumented: 'not reporting')" do
      user!()
      set_reply({:ok, 200, ~s({"status":"ok"})})
      with_key("test-key")

      assert :ok = FleetPush.perform(%Oban.Job{args: %{}})

      assert [{url, headers, body}] = calls()
      assert url == "http://fleet.test/ingest"

      auth = headers |> Enum.map(fn {k, v} -> {String.downcase(k), v} end) |> Map.new()
      assert auth["authorization"] == "Bearer test-key"
      assert auth["content-type"] =~ "application/json"

      payload = Jason.decode!(body)
      assert payload["users_total"] == nil
      assert payload["users_active_30d"] == nil
      assert payload["revenue_mtd"] == nil
      assert payload["meta"]["worker"] == "FleetPush"
      assert payload["meta"]["app_version"] != nil
      # reported_at truncated to the minute
      assert payload["reported_at"] =~ ~r/T\d{2}:\d{2}:00Z$/
    end

    test "a configured provider's integers flow through; a real zero stays 0" do
      Application.put_env(:annotate, FleetPush,
        key: "k",
        url: "http://fleet.test/ingest",
        http_client: __MODULE__.StubClient,
        metrics_provider: __MODULE__.TestProvider
      )

      payload = FleetPush.build_payload()
      assert payload["users_total"] == 7
      assert payload["users_active_30d"] == 2
      assert payload["revenue_mtd"] == %{"minor" => 0, "currency" => "usd"}
    end

    test "provider-driven counts come from the site's tables" do
      Application.put_env(:annotate, FleetPush,
        key: "k",
        url: "http://fleet.test/ingest",
        http_client: __MODULE__.StubClient,
        metrics_provider: __MODULE__.RepoProvider
      )

      keep = user!()
      user!(%{status: :deleted})
      _soft_deleted = user!(%{deleted_at: DateTime.utc_now()})

      now = DateTime.utc_now()
      old = DateTime.add(now, -40, :day)
      recent = DateTime.add(now, -5, :day)

      session!(keep.id)
      session!(keep.id, %{inserted_at: recent})
      # outside the 30-day window → not counted
      session!(keep.id, %{inserted_at: old})
      # soft-deleted session → not counted
      session!(keep.id, %{deleted_at: now})
      # session of a deleted user → not counted
      deleted = Repo.one!(from(u in User, where: u.status == :deleted, select: u.id))
      session!(deleted)

      payload = FleetPush.build_payload()
      assert payload["users_total"] == 1
      assert payload["users_active_30d"] == 1
    end

    test "returns :ok on 401 without retrying" do
      user!()
      set_reply({:ok, 401, "unauthorized"})
      with_key("bad-key")

      assert capture_log(fn ->
               assert :ok = FleetPush.perform(%Oban.Job{args: %{}})
             end) =~ "fleet_push_auth_rejected"

      assert length(calls()) == 1
    end

    test "returns :ok on payload-level 4xx without retrying" do
      user!()
      set_reply({:ok, 422, ~s({"error":"invalid_payload"})})
      with_key("k")

      assert capture_log(fn ->
               assert :ok = FleetPush.perform(%Oban.Job{args: %{}})
             end) =~ "fleet_push_rejected"

      assert length(calls()) == 1
    end

    test "returns error on 429 so Oban retries" do
      user!()
      set_reply({:ok, 429, "slow down"})
      with_key("k")

      assert {:error, {:fleet_ingest_status, 429}} = FleetPush.perform(%Oban.Job{args: %{}})
    end

    test "returns error on 5xx so Oban retries" do
      user!()
      set_reply({:ok, 500, "boom"})
      with_key("k")

      assert capture_log(fn ->
               assert {:error, {:fleet_ingest_status, 500}} =
                        FleetPush.perform(%Oban.Job{args: %{}})
             end) =~ "will retry"
    end

    test "returns error on transport failure" do
      user!()
      set_reply({:error, :stub_transport_error})
      with_key("k")

      assert {:error, {:fleet_ingest_unreachable, :stub_transport_error}} =
               FleetPush.perform(%Oban.Job{args: %{}})
    end

    test "never logs the key or the auth header" do
      user!()
      key = "super-secret-fleet-key-do-not-leak"
      set_reply({:ok, 500, "boom"})
      with_key(key)

      logs =
        capture_log(fn ->
          _ = FleetPush.perform(%Oban.Job{args: %{}})
        end)

      refute logs =~ key
      refute logs =~ "Bearer"
    end
  end

  describe "real default HTTP client" do
    test "the configured default client module resolves and is transport-capable" do
      # Regression guard: a default client named with a typo'd atom (or a
      # module that never compiles) passes a stubbed suite and crashes the
      # first prod push. Drive the REAL shipped-config client against a port
      # with no listener and expect a transport error, not a crash.
      client = Keyword.get(base_cfg(), :http_client, FleetPush.ReqClient)

      assert {:module, client} = Code.ensure_compiled(client)

      assert {:error, _reason} =
               client.post(
                 "http://127.0.0.1:1/ingest",
                 [{"content-type", "application/json"}],
                 "{}"
               )
    end
  end

  describe "oban wiring" do
    test "cron entry points at a compiled FleetPush module whose queue is declared" do
      cfg = Application.get_env(:annotate, Oban, [])
      queues = Keyword.get(cfg, :queues, [])

      cron_mods =
        cfg
        |> Keyword.get(:plugins, [])
        |> Enum.flat_map(fn
          {Oban.Plugins.Cron, opts} ->
            opts |> Keyword.get(:crontab, []) |> Enum.map(&elem(&1, 1))

          _ ->
            []
        end)

      # Match the cron entry by module-name suffix so this test can never be
      # defeated by a spelling drift between config.exs and the worker module.
      worker =
        Enum.find(cron_mods, fn m ->
          is_atom(m) and function_exported?(m, :__info__, 1) and
            m |> Module.split() |> List.last() == "FleetPush"
        end)

      assert worker, "expected a Cron entry for a FleetPush module"

      # Oban 2.18: worker options live in __opts__/0 (no public queue/0)
      queue = worker.__opts__() |> Keyword.fetch!(:queue)

      assert Keyword.has_key?(queues, queue),
             "worker queue #{inspect(queue)} must be declared in Oban queues " <>
               "or cron-inserted jobs are never executed"

      # Base app config (url/source/provider) must target the SAME module.
      worker_cfg = Application.get_env(:annotate, worker, [])
      assert worker_cfg != [], "expected config :annotate, #{inspect(worker)} in config.exs"

      provider = worker_cfg[:metrics_provider]
      assert {:module, provider} = Code.ensure_compiled(provider)

      # runtime.exs must overlay the key for the same module — a typo'd module
      # atom there would silently disable the push in prod while tests stay green.
      runtime = File.read!("config/runtime.exs")
      assert runtime =~ "config :annotate, #{inspect(worker)}"
      assert runtime =~ "FLEET_INGEST_KEY"
    end
  end

  defmodule TestProvider do
    @moduledoc false
    @behaviour Annotate.FleetPush.MetricsProvider

    @impl true
    def metrics do
      %{users_total: 7, users_active_30d: 2, revenue_mtd: %{minor: 0, currency: "usd"}}
    end
  end

  defmodule RepoProvider do
    @moduledoc """
    What a real site provider looks like: counts live users and distinct
    recent-session owners straight off the schema.
    """

    @behaviour Annotate.FleetPush.MetricsProvider

    import Ecto.Query

    @impl true
    def metrics do
      cutoff = DateTime.add(DateTime.utc_now(), -30, :day)

      users_total =
        from(u in User, where: is_nil(u.deleted_at) and u.status not in [:deleted, :suspended])
        |> Repo.aggregate(:count)

      active_30d =
        from(s in UserSession,
          join: u in User,
          on: u.id == s.user_id,
          where: s.inserted_at >= ^cutoff,
          where: is_nil(s.deleted_at),
          where: is_nil(u.deleted_at) and u.status not in [:deleted, :suspended],
          select: count(s.user_id, :distinct)
        )
        |> Repo.one()

      %{users_total: users_total, users_active_30d: active_30d, revenue_mtd: nil}
    end
  end
end
