defmodule OtelDisabledTest do
  @moduledoc """
  Regression test: with no OTEL_EXPORTER_OTLP_ENDPOINT the OpenTelemetry SDK
  must start disabled (no span processors, no exporters). Before the fix the
  default batch processor exported to http://localhost:4318 and retried
  forever, spamming deploy logs with failed_connect errors.
  """
  use ExUnit.Case, async: false
  # async: false — Annotate.ObservabilityLiveTest restarts the SDK globally
  # (stop → sdk_disabled: false → start) to prove live-span log correlation;
  # this test asserts the disabled state, so the two must not interleave.

  test "SDK starts disabled when OTLP endpoint is unset" do
    assert Application.get_env(:opentelemetry, :sdk_disabled) == true
    assert :supervisor.which_children(:opentelemetry_sup) == []
  end
end
