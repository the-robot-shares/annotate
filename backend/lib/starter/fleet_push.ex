defmodule Starter.FleetPush do
  @moduledoc """
  Daily push of fleet-dashboard metrics (fleet.noizu.com) — vendored fleet
  instrumentation shipped with the hologram-start-app template.

  Scheduled via Oban Cron at 09:05 UTC (see `config/config.exs`). POSTs a
  single JSON document to the fleet ingest endpoint, authenticated with
  `FLEET_INGEST_KEY` (bearer). Behaviour:

    * key missing/blank → one :info log, `:ok`. Never crashes, never retries —
      the pod may simply not be provisioned the key yet.
    * any 2xx (including a `{"status":"duplicate"}` body) → `:ok`.
    * 401/403 → :error log tagged `fleet_push_auth_rejected`, `:ok`. A bad key
      is boot-pinned app env, so a retry cannot succeed — remediation is
      mint/rotate the key, then restart the pod.
    * other 4xx (except 408/429) → :error log tagged `fleet_push_rejected`,
      `:ok`. Payload-level rejections won't fix themselves on retry.
    * 408 / 429 / 5xx / timeout / transport error → `{:error, reason}` so Oban
      retries (max_attempts 3).

  Metric values come from the site's `#{inspect(__MODULE__)}.MetricsProvider`
  implementation (`config :starter, __MODULE__, metrics_provider: ...`).
  Semantics are defined once, fleet-wide:

    * `nil` means "this site has no source for this metric" — fleet renders it
      as "not reporting". NEVER send 0 when there is no source.
    * A real zero (the source exists, the count/sum is genuinely 0 — e.g. a
      billing table with no paid rows this month) is sent as 0.

  Never logs the ingest key or the Authorization header.
  """

  use Oban.Worker, queue: :fleet_push, max_attempts: 3

  require Logger

  @default_url "https://fleet.noizu.com/api/v1/ingest/metrics"

  @impl Oban.Worker
  def perform(_job) do
    key = cfg(:key)

    if key in [nil, ""] do
      Logger.info("FleetPush: no FLEET_INGEST_KEY configured; skipping fleet push")
      :ok
    else
      push(key)
    end
  end

  @doc """
  Runs one push inline (outside Oban) — for `bin/<app> rpc` / release evals:

      bin/<app> eval "#{inspect(__MODULE__)}.push_now()"
  """
  @spec push_now() :: :ok | {:error, term()}
  def push_now, do: perform(%Oban.Job{args: %{}})

  # -- push ---------------------------------------------------------------

  defp push(key) do
    payload = build_payload() |> Jason.encode!()
    url = cfg(:url, @default_url)
    headers = [{"authorization", "Bearer " <> key}, {"content-type", "application/json"}]

    case http_client().post(url, headers, payload) do
      {:ok, status, _body} when status in 200..299 ->
        Logger.info("FleetPush: fleet metrics accepted by #{url} (#{status})")
        :ok

      {:ok, status, _body} when status in [401, 403] ->
        Logger.error(
          "fleet_push_auth_rejected status=#{status}; not retrying — key is " <>
            "boot-pinned app env, mint/rotate FLEET_INGEST_KEY then restart the pod"
        )

        :ok

      {:ok, status, _body} when status in 400..499 and status not in [408, 429] ->
        Logger.error(
          "fleet_push_rejected status=#{status}; not retrying — payload-level " <>
            "rejection won't fix itself (408/429/5xx DO retry)"
        )

        :ok

      {:ok, status, _body} ->
        Logger.error("FleetPush: fleet ingest failed (#{status}); will retry")
        {:error, {:fleet_ingest_status, status}}

      {:error, reason} ->
        Logger.error("FleetPush: fleet ingest unreachable; will retry")
        {:error, {:fleet_ingest_unreachable, reason}}
    end
  end

  # -- payload ------------------------------------------------------------

  @doc false
  def build_payload do
    now = DateTime.utc_now()
    metrics = metrics_provider().metrics()

    %{
      "reported_at" =>
        now
        |> DateTime.truncate(:second)
        |> then(fn dt -> %{dt | second: 0} end)
        |> DateTime.to_iso8601(),
      "users_total" => Map.get(metrics, :users_total),
      "users_active_30d" => Map.get(metrics, :users_active_30d),
      "revenue_mtd" => revenue_mtd_json(Map.get(metrics, :revenue_mtd)),
      "meta" => meta()
    }
  end

  defp revenue_mtd_json(nil), do: nil

  defp revenue_mtd_json(%{minor: minor, currency: currency}) when is_integer(minor) do
    %{"minor" => minor, "currency" => to_string(currency)}
  end

  defp meta do
    %{"source" => cfg(:source, "starter"), "worker" => "FleetPush"}
    |> maybe_put_version()
  end

  defp maybe_put_version(meta) do
    case Application.spec(:starter, :vsn) do
      nil -> meta
      vsn -> Map.put(meta, "app_version", to_string(vsn))
    end
  end

  # -- plumbing -----------------------------------------------------------

  defp cfg(key, default \\ nil) do
    Application.get_env(:starter, __MODULE__, [])
    |> Keyword.get(key, default)
  end

  defp metrics_provider, do: cfg(:metrics_provider, __MODULE__.MetricsProvider.Nil)
  defp http_client, do: cfg(:http_client, ReqClient)

  defmodule MetricsProvider do
    @moduledoc """
    One-callback behaviour a site implements to report real metrics:

        defmodule MyApp.FleetMetrics do
          @behaviour Starter.FleetPush.MetricsProvider

          @impl true
          def metrics do
            %{users_total: 3, users_active_30d: 1, revenue_mtd: nil}
          end
        end

    then:

        config :starter, Starter.FleetPush, metrics_provider: MyApp.FleetMetrics

    Return `nil` for any metric the site has no source for — never 0.
    """

    @callback metrics() :: %{
                optional(:users_total) => non_neg_integer() | nil,
                optional(:users_active_30d) => non_neg_integer() | nil,
                optional(:revenue_mtd) => %{minor: non_neg_integer(), currency: String.t()} | nil
              }

    defmodule Nil do
      @moduledoc """
      Default provider: no sources wired yet — every metric `nil`, so a freshly
      scaffolded site pushes "not reporting" for all three and still shows a
      recent daily push on the fleet dashboard.
      """

      @behaviour Starter.FleetPush.MetricsProvider

      @impl Starter.FleetPush.MetricsProvider
      def metrics, do: %{users_total: nil, users_active_30d: nil, revenue_mtd: nil}
    end
  end

  defmodule Client do
    @moduledoc """
    HTTP behaviour for `#{inspect(Starter.FleetPush)}`, injectable via
    `config :starter, #{inspect(Starter.FleetPush)}, http_client: ...` (tests).
    """

    @callback post(url :: String.t(), headers :: [{String.t(), String.t()}], body :: binary()) ::
                {:ok, status :: pos_integer(), body :: term()} | {:error, term()}
  end

  defmodule ReqClient do
    @moduledoc """
    Default `#{inspect(Starter.FleetPush)}` HTTP backend built on Req.

    `retry: false` — retries are Oban's job, not the HTTP client's.
    """

    @behaviour Starter.FleetPush.Client

    @impl Starter.FleetPush.Client
    def post(url, headers, body) do
      case Req.post(url, headers: headers, body: body, receive_timeout: 15_000, retry: false) do
        {:ok, %Req.Response{status: status, body: body}} -> {:ok, status, body}
        {:error, error} -> {:error, error}
      end
    end
  end
end
