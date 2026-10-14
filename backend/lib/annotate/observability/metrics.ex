defmodule Annotate.Observability.Metrics do
  @moduledoc """
  OTel metrics for the BEAM VM and Oban, exported over OTLP to the SigNoz
  collector.

  Phase-1 pilot gap (therrobotplans, 2026-10): traces flowed but the services
  page showed zero metric samples — the Erlang traces SDK ships no VM metrics
  and the traces-only stack never created instruments. This module adds the
  metrics leg on `opentelemetry_experimental` (0.6.x): an `otel_metric_reader`
  periodic reader exports to the same OTLP endpoint the traces exporter uses
  (reader config in `config/runtime.exs`, only set when the endpoint env is
  set).

  Metric names follow the telemetry_poller canonical dotted names the fleet
  dashboard module queries by default (`vm.memory.total`,
  `vm.total_run_queue_lengths.total`) — conventions section 5. The Oban
  instruments are `oban.job.count` (counter) and `oban.job.duration`
  (histogram, unit `s`), attributed by queue/worker only.

  Disabled path (dev/test, no endpoint): `setup/0` is called from
  `application.ex` unconditionally and returns `:disabled` without creating
  instruments or attaching handlers — the meter provider never starts (see
  `config/runtime.exs`), so nothing is recorded or exported anywhere.

  PII: none of these instruments or attributes carry user data — only BEAM
  counters and Oban queue/worker names (conventions section 7). Job args,
  ids, and error bodies never enter attributes.

  Value functions mirror `telemetry_poller_builtin` exactly (the dep ships in
  this repo): total = `statistics(:total_run_queue_lengths_all)`, cpu =
  `statistics(:total_run_queue_lengths)`, io = total - cpu (OTP 29 returns
  integers, not the 3-tuple).
  """

  @endpoint_env "OTEL_EXPORTER_OTLP_ENDPOINT"

  # Instrumentation scope for the meter — one namespace for all instruments.
  @meter_scope "annotate.otel_metrics"
  @handler_id "annotate.otel_metrics.oban"

  require Record

  # The meter server groups instruments per instrumentation scope and the OTLP
  # proto builder reads #instrumentation_scope{} records — a bare string scope
  # crashes the reader at export time (badrecord), so always pass the record
  # the API declares.
  Record.defrecordp(
    :instrumentation_scope,
    Record.extract(:instrumentation_scope,
      from_lib: "opentelemetry_api/include/opentelemetry.hrl"
    )
  )

  defp scope, do: instrumentation_scope(name: @meter_scope)

  @doc """
  Installs the metrics leg. Idempotent: telemetry handlers are attached once,
  re-running is a no-op.

  Returns `:disabled` when the OTLP endpoint env is unset (dev/test/SDK-off
  chart), `:ok` when instruments and handlers are installed.
  """
  @spec setup() :: :ok | :disabled
  def setup do
    if endpoint_set?() do
      meter = :otel_meter_provider.get_meter(scope())

      install_vm_instruments(meter)
      install_oban_instruments(meter)
      install_oban_handlers()

      :ok
    else
      :disabled
    end
  end

  @doc false
  def endpoint_set? do
    case System.get_env(@endpoint_env) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  ## BEAM VM instruments (observable gauges — sampled at reader collect time)

  @doc """
  VM gauge specs: `{metric_name, value_fun}` pairs, sampled when the metric
  reader collects. Each value_fun reads only VM counters.
  """
  def vm_specs do
    [
      {:"vm.memory.total", fn -> :erlang.memory(:total) end},
      {:"vm.total_run_queue_lengths.total", fn -> queue_total() end},
      {:"vm.total_run_queue_lengths.cpu", fn -> queue_cpu() end},
      {:"vm.total_run_queue_lengths.io", fn -> queue_total() - queue_cpu() end},
      {:"vm.system_counts.process_count", fn -> :erlang.system_info(:process_count) end},
      {:"vm.system_counts.atom_count", fn -> :erlang.system_info(:atom_count) end},
      {:"vm.system_counts.port_count", fn -> :erlang.system_info(:port_count) end},
      {:"vm.system_counts.ets_count", fn -> length(:ets.all()) end}
    ]
  end

  defp install_vm_instruments(meter) do
    for {name, value_fun} <- vm_specs() do
      :otel_meter.create_observable_gauge(
        meter,
        name,
        fn _measurement -> [{value_fun.(), %{}}] end,
        [],
        %{description: "BEAM VM (telemetry_poller-canonical name)"}
      )
    end

    :ok
  end

  # Mirrors telemetry_poller_builtin (see moduledoc): on OTP 29 both BIFs
  # return integers, and io is derived, not a third BIF.
  defp queue_total, do: :erlang.statistics(:total_run_queue_lengths_all)

  defp queue_cpu, do: :erlang.statistics(:total_run_queue_lengths)

  ## Oban job metrics (sync counter + histogram via :telemetry)

  @doc """
  Telemetry events the Oban instruments ride.
  """
  def oban_events do
    [[:oban, :job, :stop], [:oban, :job, :exception]]
  end

  @doc """
  Builds the attribute map for an Oban job event. Queue is normalized to a
  string; worker is Oban's own worker-module string. No job args, ids, or
  error bodies ever make it into attributes.
  """
  def oban_attrs(_event, metadata, status) do
    job = Map.get(metadata, :job) || %{}

    %{
      "queue" => metric_name(Map.get(job, :queue)),
      "worker" => metric_name(Map.get(job, :worker)),
      "status" => Atom.to_string(status)
    }
  end

  # Guards the nil -> "nil" to_string trap: a missing queue/worker renders as
  # the empty string instead of raising inside the handler.
  defp metric_name(nil), do: ""

  defp metric_name(value) when is_atom(value) and not is_boolean(value),
    do: Atom.to_string(value)

  defp metric_name(value) when is_binary(value), do: value

  defp metric_name(value), do: to_string(value)

  @doc """
  Converts an Oban `duration` measurement (native time units) to seconds
  (float) — the histogram carries unit `s` on the instrument, no unit suffix
  in the name.
  """
  def duration_seconds(duration) when is_integer(duration) or is_float(duration) do
    duration
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1_000_000)
  end

  @doc """
  Telemetry handler. Records by name against the meter — instruments are
  pre-created in `setup/0` (so the duration histogram carries unit `s`); the
  record itself is name-based per the experimental SDK API
  (`:otel_counter.add/5`, `:otel_histogram.record/5`).

  Never raises: the metrics leg must not take a job execution down with it.
  """
  def handle_event(_event, measurements, metadata, :ok) do
    meter = :otel_meter_provider.get_meter(@meter_scope)
    ctx = :otel_ctx.new()

    status = if Map.has_key?(metadata, :error), do: :error, else: :success
    attrs = oban_attrs(nil, metadata, status)

    :otel_counter.add(ctx, meter, :"oban.job.count", 1, attrs)

    duration = Map.get(measurements, :duration)

    if is_number(duration) do
      :otel_histogram.record(ctx, meter, :"oban.job.duration", duration_seconds(duration), attrs)
    end

    :ok
  rescue
    # Never take a job execution down with the metrics leg.
    _ -> :ok
  end

  defp install_oban_instruments(meter) do
    :otel_meter.create_counter(meter, :"oban.job.count", %{
      description: "Oban jobs executed, by queue/worker/status"
    })

    :otel_meter.create_histogram(meter, :"oban.job.duration", %{
      description: "Oban job execution duration",
      unit: "s"
    })

    :ok
  end

  defp install_oban_handlers do
    already? =
      oban_events()
      |> Enum.flat_map(&:telemetry.list_handlers/1)
      |> Enum.any?(&(&1.id == @handler_id))

    if already? do
      :ok
    else
      :telemetry.attach_many(@handler_id, oban_events(), &__MODULE__.handle_event/4, :ok)
    end
  end
end
