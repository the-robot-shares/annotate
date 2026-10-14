defmodule Annotate.Application do
  @moduledoc false
  use Application
  require Logger

  @impl true
  # <REMOVED UUID HERE> start :: auto-generated pointer for public function start
  def start(_type, _args) do
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:annotate, :repo])
    OpentelemetryBandit.setup()
    OpentelemetryOban.setup()
    Annotate.Observability.Metrics.setup()

    samly_children =
      if Application.get_env(:annotate, :saml_enabled) do
        [Samly.Provider]
      else
        []
      end

    children =
      [
        AnnotateWeb.Telemetry,
        Annotate.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:annotate, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:annotate, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Annotate.PubSub},
        Annotate.Redis,
        Noizu.LiveViewEventServer,
        {Oban, Application.fetch_env!(:annotate, Oban)}
      ] ++
        samly_children ++
        [
          Annotate.Events.WebhookHandler,
          AnnotateWeb.Endpoint
        ]

    opts = [strategy: :one_for_one, name: Annotate.Supervisor]

    with {:ok, _pid} = ok <- Supervisor.start_link(children, opts) do
      warm_sref_handlers()
      ok
    end
  end

  # Build the sref -> entity handler table at boot (noizu_labs_entities >= 0.3.4)
  # so the first requests after a deploy don't pay the cold build (the Guardian
  # subject `ref.user-session.*` resolves through it). Never fails boot: the
  # table is still built lazily on first lookup if this raises.
  defp warm_sref_handlers() do
    Annotate.EntityRepo.warm_sref_handlers()
  rescue
    e -> Logger.warning("sref handler warm-up failed: #{Exception.message(e)}")
  catch
    kind, reason -> Logger.warning("sref handler warm-up failed: #{inspect({kind, reason})}")
  end

  @impl true
  # <REMOVED UUID HERE> config_change :: auto-generated pointer for public function config_change
  def config_change(changed, _new, removed) do
    AnnotateWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    System.get_env("RELEASE_NAME") == nil
  end
end
