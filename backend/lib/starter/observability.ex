defmodule Starter.Observability do
  @moduledoc """
  OpenTelemetry wiring helpers.

  Runtime behaviour (see `config/runtime.exs`): the whole OTel stack is a
  no-op unless `OTEL_EXPORTER_OTLP_ENDPOINT` is set — the SDK starts with
  `sdk_disabled: true`, no exporter, no span processors, zero connection
  attempts. With an endpoint set, resources/sampler/protocol are built from
  the functions here.

  House conventions: `docs/observability/OTEL-CONVENTIONS.md` in the
  trl-infra monorepo (service.name = fleet site key, service.namespace =
  "portfolio", no k8s.* attrs from the app).
  """

  @default_service_name "starter-backend"
  @default_namespace "portfolio"

  # Env keys the resource builder consumes (all optional).
  @resource_env_keys ~w(OTEL_SERVICE_NAME FLEET_SITE_KEY OTEL_RESOURCE_ATTRIBUTES)

  @doc """
  Returns the env keys this module reads, so callers can snapshot a minimal
  env map (keeps `resource_attributes/1` pure and unit-testable).
  """
  @spec resource_env_keys() :: [String.t()]
  def resource_env_keys, do: @resource_env_keys

  @doc """
  Builds OpenTelemetry resource attributes from a map of OS environment
  variables (string keys, string or nil values). Pure: no System/Application
  reads — pass `%{}` in tests.

  Layers, highest precedence first:

    * `OTEL_SERVICE_NAME` env var → `service.name`
    * `OTEL_RESOURCE_ATTRIBUTES` (W3C `k=v,k=v` list) attribute
    * `FLEET_SITE_KEY` env var → `service.name` fallback (fleet site key)
    * built-in default `"#{@default_service_name}"`

  Always present: `service.name`, `service.namespace` (default
  `#{@default_namespace}`). Optional: `deployment.environment` and
  `service.version` — set them via `OTEL_RESOURCE_ATTRIBUTES` (the chart
  does) or pass-through attributes are preserved.
  """
  @spec resource_attributes(%{optional(String.t()) => String.t() | nil}) :: %{
          String.t() => String.t()
        }
  def resource_attributes(env) when is_map(env) do
    base = parse_resource_attributes(env["OTEL_RESOURCE_ATTRIBUTES"])

    base
    |> Map.delete("service.name")
    |> Map.merge(%{"service.namespace" => base["service.namespace"] || @default_namespace})
    |> Map.put("service.name", service_name(env, base))
  end

  defp service_name(env, base) do
    env["OTEL_SERVICE_NAME"] || base["service.name"] ||
      present(env["FLEET_SITE_KEY"]) || @default_service_name
  end

  @doc """
  Maps an `OTEL_TRACES_SAMPLER` value (+ `OTEL_TRACES_SAMPLER_ARG`) to the
  OpenTelemetry Erlang SDK sampler spec. Unknown/missing sampler names fall
  back to `parentbased_traceidratio` (the OTel default family); a bad
  sampler arg falls back to 1.0.
  """
  @spec sampler_spec(String.t() | nil, String.t() | nil) ::
          :always_on
          | :always_off
          | {:trace_id_ratio_based, float()}
          | {:parent_based, %{root: term()}}
  def sampler_spec(name, arg \\ nil) do
    ratio = parse_float(arg) || 1.0

    case name do
      "always_on" -> :always_on
      "always_off" -> :always_off
      "traceidratio" -> {:trace_id_ratio_based, ratio}
      "trace_id_ratio_based" -> {:trace_id_ratio_based, ratio}
      "parentbased_always_on" -> {:parent_based, %{root: :always_on}}
      "parentbased_always_off" -> {:parent_based, %{root: :always_off}}
      # "parentbased_traceidratio" (OTel default) and anything unknown.
      _ -> {:parent_based, %{root: {:trace_id_ratio_based, ratio}}}
    end
  end

  @doc """
  Maps an `OTEL_EXPORTER_OTLP_PROTOCOL` value to the exporter's protocol
  atom. Anything but "grpc" maps to `:http_protobuf` (the house default —
  SigNoz collector :4318).
  """
  @spec protocol(String.t() | nil) :: :grpc | :http_protobuf
  def protocol(nil), do: :http_protobuf
  def protocol("grpc"), do: :grpc
  def protocol(_), do: :http_protobuf

  # ── Internals ─────────────────────────────────────────────────────

  defp parse_resource_attributes(nil), do: %{}
  defp parse_resource_attributes(""), do: %{}

  defp parse_resource_attributes(raw) when is_binary(raw) do
    raw
    |> String.split(",", trim: true)
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [k, v] -> Map.put(acc, String.trim(k), URI.decode(String.trim(v)))
        _ -> acc
      end
    end)
  end

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present(value), do: value

  defp parse_float(raw) do
    case Float.parse(to_string(raw || "")) do
      {f, _} -> f
      :error -> nil
    end
  end
end
