defmodule AnnotateWeb.Plugs.OtelLoggerMetadata do
  @behaviour Plug

  @impl true
  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(opts), do: opts

  @impl true
  # <REMOVED UUID HERE> call :: auto-generated pointer for public function call
  def call(conn, _opts) do
    case OpenTelemetry.Tracer.current_span_ctx() do
      :undefined ->
        conn

      span_ctx ->
        trace_id =
          span_ctx
          |> OpenTelemetry.Span.trace_id()
          |> Integer.to_string(16)
          |> String.downcase()
          |> String.pad_leading(32, "0")

        span_id =
          span_ctx
          |> OpenTelemetry.Span.span_id()
          |> Integer.to_string(16)
          |> String.downcase()
          |> String.pad_leading(16, "0")

        Logger.metadata(trace_id: trace_id, span_id: span_id)
        conn
    end
  rescue
    _ -> conn
  end
end
