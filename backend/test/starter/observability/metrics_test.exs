defmodule Starter.Observability.MetricsTest do
  use ExUnit.Case, async: true

  alias Starter.Observability.Metrics

  describe "setup/0" do
    test "is a no-op when the OTLP endpoint env is unset (dev/test)" do
      assert Metrics.endpoint_set?() == false

      # Test env runs with no collector configured: setup must refuse to
      # touch the meter provider (which never starts) and attach nothing.
      assert Metrics.setup() == :disabled

      # Other bridges may attach their own oban handlers at boot; ours must
      # not be among them when the endpoint is unset.
      ours =
        Metrics.oban_events()
        |> Enum.flat_map(&:telemetry.list_handlers/1)
        |> Enum.any?(&(&1.id == "starter.otel_metrics.oban"))

      refute ours
    end
  end

  describe "vm_specs/0" do
    test "covers the telemetry_poller-canonical instruments the dashboard keys on" do
      names = Metrics.vm_specs() |> Enum.map(&elem(&1, 0))

      assert :"vm.memory.total" in names
      assert :"vm.total_run_queue_lengths.total" in names
      assert :"vm.total_run_queue_lengths.cpu" in names
      assert :"vm.total_run_queue_lengths.io" in names
      assert :"vm.system_counts.process_count" in names
    end

    test "names are unique and dotted" do
      names = Metrics.vm_specs() |> Enum.map(&elem(&1, 0))

      assert length(names) == length(Enum.uniq(names))
      assert Enum.all?(names, &(&1 |> Atom.to_string() |> String.contains?(".")))
    end

    test "every value_fun reads a real BEAM counter (positive number)" do
      for {_name, fun} <- Metrics.vm_specs() do
        value = fun.()

        assert is_number(value)
        assert value >= 0
      end
    end
  end

  describe "oban_attrs/3" do
    test "renders queue and worker as strings, never job data" do
      worker = "Metrics.Workers.FleetPushWorker"

      metadata = %{
        job: %{queue: :default, worker: worker, args: %{"email" => "pii@example.com"}, id: 42}
      }

      attrs = Metrics.oban_attrs(nil, metadata, :success)

      assert attrs == %{"queue" => "default", "worker" => worker, "status" => "success"}

      # PII guard: job args and ids never leak into attributes.
      refute attrs |> Map.values() |> Enum.any?(&String.contains?(&1, "pii"))
    end

    test "a missing job renders empty strings, never raises" do
      assert Metrics.oban_attrs(nil, %{}, :error) == %{
               "queue" => "",
               "worker" => "",
               "status" => "error"
             }
    end
  end

  describe "duration_seconds/1" do
    test "converts native durations proportionally into seconds" do
      one = Metrics.duration_seconds(1_000_000_000)

      assert one > 0
      assert Metrics.duration_seconds(2_000_000_000) == 2 * one
    end
  end

  describe "handle_event/4 with the SDK disabled (noop meter)" do
    test "records nothing and never raises on a successful job event" do
      measurements = %{duration: System.monotonic_time(), queue_time: 0}
      metadata = %{job: %{queue: :default, worker: "Metrics.Workers.FleetPushWorker"}}

      assert Metrics.handle_event([:oban, :job, :stop], measurements, metadata, :ok) == :ok
    end

    test "tolerates an exception event with an error and a missing duration" do
      metadata = %{job: %{queue: :mailers, worker: "Metrics.Workers.Broken"}}

      assert Metrics.handle_event([:oban, :job, :exception], %{}, metadata, :ok) == :ok
    end

    test "tolerates total garbage without raising" do
      assert Metrics.handle_event([:oban, :job, :stop], %{}, %{}, :ok) == :ok
    end
  end

  describe "oban_events/0" do
    test "rides the job stop and exception events" do
      assert Metrics.oban_events() == [[:oban, :job, :stop], [:oban, :job, :exception]]
    end
  end
end
