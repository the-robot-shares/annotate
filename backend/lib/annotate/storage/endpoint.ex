defmodule Annotate.Storage.Endpoint do
  @moduledoc """
  Splits an S3 endpoint setting into the `scheme`/`host`/`port` keys ExAws
  expects. Accepts a bare `host[:port]` (scheme from `default_scheme`) or a
  full URL (`"http://minio-service.infra.svc.cluster.local:9000"`).

  Called from `config/runtime.exs`; passing a full URL straight through as
  ExAws `:host` yields malformed presigned urls (`"http://http:%3A//…"`).
  """

  @spec parse(String.t() | nil, String.t()) :: keyword()
  def parse(raw, default_scheme \\ "https://")
  def parse(nil, _default_scheme), do: []

  def parse(raw, default_scheme) when is_binary(raw) do
    case String.trim(raw) do
      "" ->
        []

      trimmed ->
        uri =
          if String.contains?(trimmed, "://"),
            do: URI.parse(trimmed),
            else: URI.parse(default_scheme <> trimmed)

        case uri do
          %URI{scheme: scheme, host: host}
          when is_binary(scheme) and is_binary(host) and host != "" ->
            [scheme: scheme <> "://", host: host, port: uri.port || default_port(scheme)]

          _ ->
            []
        end
    end
  end

  defp default_port("https"), do: 443
  defp default_port(_), do: 80
end
