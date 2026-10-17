defmodule Annotate.Storage do
  @moduledoc """
  S3/MinIO access.

  Two endpoints:

  - the internal endpoint (`:scheme`/`:host`/`:port`) for server-side calls
    (`delete_object`, media variants), typically the in-cluster MinIO service;
  - the public endpoint (`:public` — `[scheme:, host:, port:]`) used to sign
    presigned PUT/GET urls. Those urls are handed to the browser, so they must
    name a host the browser can reach (and that its CSP allows). When `:public`
    is empty the internal endpoint is used (dev/test, single-endpoint setups).
  """

  @default_expiry 3600

  # <REMOVED UUID HERE> presigned_upload_url :: auto-generated pointer for public function presigned_upload_url
  def presigned_upload_url(key, content_type \\ "application/octet-stream") do
    config = presign_config()

    {:ok, url} =
      ExAws.S3.presigned_url(
        ExAws.Config.new(:s3, config),
        :put,
        config[:bucket],
        key,
        expires_in: @default_expiry,
        headers: [{"content-type", content_type}]
      )

    url
  end

  # <REMOVED UUID HERE> presigned_download_url :: auto-generated pointer for public function presigned_download_url
  def presigned_download_url(key, expires_in \\ @default_expiry) do
    config = presign_config()

    {:ok, url} =
      ExAws.S3.presigned_url(
        ExAws.Config.new(:s3, config),
        :get,
        config[:bucket],
        key,
        expires_in: expires_in
      )

    url
  end

  # <REMOVED UUID HERE> delete_object :: auto-generated pointer for public function delete_object
  def delete_object(key) do
    config = config()

    ExAws.S3.delete_object(config[:bucket], key)
    |> ExAws.request(Keyword.delete(config, :public))
  end

  @doc """
  Browser-facing origin of presigned urls (`"https://minio.example.com"`), or
  nil when storage is unconfigured. Used to extend CSP img-src/connect-src.
  """
  def public_origin do
    config = presign_config()

    case {config[:scheme], config[:host]} do
      {scheme, host} when is_binary(scheme) and is_binary(host) and host != "" ->
        port =
          case {scheme, config[:port]} do
            {_, nil} -> ""
            {"https://", 443} -> ""
            {"http://", 80} -> ""
            {_, port} -> ":#{port}"
          end

        scheme <> host <> port

      _ ->
        nil
    end
  end

  defp presign_config do
    config = config()

    case Keyword.get(config, :public, []) do
      public when is_list(public) and public != [] ->
        config |> Keyword.delete(:public) |> Keyword.merge(public)

      _ ->
        Keyword.delete(config, :public)
    end
  end

  defp config do
    Application.get_env(:annotate, __MODULE__, [])
  end
end
