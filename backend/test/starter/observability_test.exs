defmodule Starter.ObservabilityTest do
  @moduledoc """
  Unit tests for the pure OTel helpers (resource attributes, sampler spec,
  protocol). The no-op behaviour in dev/test is additionally pinned by
  OtelDisabledTest; log correlation lives in Starter.ObservabilityLiveTest.
  """

  use ExUnit.Case, async: true

  alias Starter.Observability

  describe "resource_attributes/1" do
    test "defaults: service.name starter-backend, service.namespace portfolio" do
      assert Observability.resource_attributes(%{}) == %{
               "service.name" => "starter-backend",
               "service.namespace" => "portfolio"
             }
    end

    test "OTEL_SERVICE_NAME wins over everything" do
      attrs =
        Observability.resource_attributes(%{
          "OTEL_SERVICE_NAME" => "my-site",
          "FLEET_SITE_KEY" => "other-site",
          "OTEL_RESOURCE_ATTRIBUTES" => "service.name=from-attrs"
        })

      assert attrs["service.name"] == "my-site"
    end

    test "FLEET_SITE_KEY is the service.name fallback" do
      attrs = Observability.resource_attributes(%{"FLEET_SITE_KEY" => "trackimo"})
      assert attrs["service.name"] == "trackimo"
    end

    test "nil/blank env values are handled" do
      attrs =
        Observability.resource_attributes(%{
          "OTEL_SERVICE_NAME" => nil,
          "OTEL_RESOURCE_ATTRIBUTES" => nil,
          "FLEET_SITE_KEY" => ""
        })

      assert attrs["service.name"] == "starter-backend"
    end

    test "parses OTEL_RESOURCE_ATTRIBUTES k=v list and keeps extra attrs" do
      attrs =
        Observability.resource_attributes(%{
          "OTEL_RESOURCE_ATTRIBUTES" =>
            "deployment.environment=prod,service.version=sha-abc123,service.namespace=team-x"
        })

      assert attrs["deployment.environment"] == "prod"
      assert attrs["service.version"] == "sha-abc123"
      assert attrs["service.namespace"] == "team-x"
    end

    test "service.namespace default applies when attrs omit it" do
      attrs =
        Observability.resource_attributes(%{
          "OTEL_RESOURCE_ATTRIBUTES" => "deployment.environment=stage"
        })

      assert attrs["service.namespace"] == "portfolio"
      assert attrs["deployment.environment"] == "stage"
    end

    test "service.name in attrs is honored" do
      attrs =
        Observability.resource_attributes(%{
          "OTEL_RESOURCE_ATTRIBUTES" => "service.name=attrs-name"
        })

      assert attrs["service.name"] == "attrs-name"
    end

    test "malformed attr pairs are skipped" do
      attrs = Observability.resource_attributes(%{"OTEL_RESOURCE_ATTRIBUTES" => "garbage,ok=1,,"})
      assert attrs["ok"] == "1"
      refute Map.has_key?(attrs, "garbage")
    end
  end

  describe "sampler_spec/2" do
    test "parentbased_traceidratio is the parent-based ratio sampler" do
      assert Observability.sampler_spec("parentbased_traceidratio", "1.0") ==
               {:parent_based, %{root: {:trace_id_ratio_based, 1.0}}}
    end

    test "unknown/missing sampler falls back to parent-based ratio" do
      assert Observability.sampler_spec(nil, "0.5") ==
               {:parent_based, %{root: {:trace_id_ratio_based, 0.5}}}
    end

    test "bad sampler arg falls back to 1.0" do
      assert Observability.sampler_spec("parentbased_traceidratio", "not-a-float") ==
               {:parent_based, %{root: {:trace_id_ratio_based, 1.0}}}
    end

    test "always_off and always_on map to SDK atoms" do
      assert Observability.sampler_spec("always_off", nil) == :always_off
      assert Observability.sampler_spec("always_on", "0") == :always_on
    end
  end

  describe "protocol/1" do
    test "grpc passes through, everything else is http_protobuf" do
      assert Observability.protocol("grpc") == :grpc
      assert Observability.protocol("http/protobuf") == :http_protobuf
      assert Observability.protocol("nonsense") == :http_protobuf
      assert Observability.protocol(nil) == :http_protobuf
    end
  end
end

defmodule StarterWeb.Plugs.OtelLoggerMetadataTest do
  @moduledoc "The endpoint plug lifts the active span's ids into logger metadata."

  use ExUnit.Case, async: true
  require Logger

  alias StarterWeb.Plugs.OtelLoggerMetadata

  test "sets trace_id/span_id from an active span" do
    require OpenTelemetry.Tracer

    OpenTelemetry.Tracer.with_span "plug-probe" do
      _conn = OtelLoggerMetadata.call(%Plug.Conn{}, nil)
      meta = Logger.metadata()

      assert byte_size(meta[:trace_id] || "") == 32
      assert Regex.match?(~r/[0-9a-f]{32}/, meta[:trace_id])
      assert Regex.match?(~r/[0-9a-f]{16}/, meta[:span_id])
    end

    # with_span detaches; metadata is process-local and remains set — clear it
    # so later assertions start clean.
  end

  test "no active span leaves metadata untouched" do
    Logger.reset_metadata([:trace_id, :span_id])
    _conn = OtelLoggerMetadata.call(%Plug.Conn{}, nil)
    assert Logger.metadata()[:trace_id] == nil
  end
end

defmodule Starter.ObservabilityLiveTest do
  @moduledoc """
  Sync (SDK restarts are app-global): a log emitted inside a live span, with
  the production plug applied, renders the trace id through the default
  formatter. Restores the sdk_disabled state for OtelDisabledTest.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  require Logger

  test "log inside a live span carries its trace_id" do
    restart_otel_sdk!()

    try do
      require OpenTelemetry.Tracer

      # test.exs pins the logger to :warning; raise globally, restore after.
      Logger.configure(level: :info)

      inside =
        capture_log(fn ->
          OpenTelemetry.Tracer.with_span "log-correlation-probe" do
            _ = StarterWeb.Plugs.OtelLoggerMetadata.call(%Plug.Conn{}, nil)
            Logger.info("probe-inside-span")
          end
        end)

      # Logger metadata is process-local; production processes are
      # per-request/per-job so ids never leak across spans there. The test
      # process is long-lived, so reset before the outside probe.
      Logger.reset_metadata([])

      outside = capture_log(fn -> Logger.info("probe-outside-span") end)

      assert inside =~ "probe-inside-span"
      assert inside =~ ~r/trace_id=[0-9a-f]{32}/

      assert outside =~ "probe-outside-span"
      refute outside =~ "trace_id="
    after
      Logger.configure(level: :warning)
      restore_otel_sdk!()
    end
  end

  # The SDK starts in test env with sdk_disabled: true (runtime.exs no-op
  # branch). Stop it, run a simple processor (dead endpoint is fine), restore.
  defp restart_otel_sdk! do
    _ = Application.stop(:opentelemetry)
    Application.put_env(:opentelemetry, :sdk_disabled, false)
    Application.put_env(:opentelemetry, :span_processor, :simple)
    {:ok, _} = Application.ensure_all_started(:opentelemetry)
    :ok
  end

  defp restore_otel_sdk! do
    _ = Application.stop(:opentelemetry)
    Application.delete_env(:opentelemetry, :span_processor)
    Application.put_env(:opentelemetry, :sdk_disabled, true)
    {:ok, _} = Application.ensure_all_started(:opentelemetry)
    :ok
  end
end
