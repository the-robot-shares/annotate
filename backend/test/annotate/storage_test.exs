defmodule Annotate.StorageTest do
  # Mutates the global Annotate.Storage app env.
  use ExUnit.Case, async: false

  alias Annotate.Storage

  setup do
    original = Application.get_env(:annotate, Storage)
    on_exit(fn -> Application.put_env(:annotate, Storage, original) end)
    :ok
  end

  defp put_storage(overrides) do
    base = [
      bucket: "annotate",
      region: "us-east-1",
      access_key_id: "test-access-key",
      secret_access_key: "test-secret-key",
      scheme: "http://",
      host: "minio-service.infra.svc.cluster.local",
      port: 9000
    ]

    Application.put_env(:annotate, Storage, Keyword.merge(base, overrides))
  end

  describe "presigned urls with a public endpoint" do
    setup do
      put_storage(public: [scheme: "https://", host: "minio.example.com", port: 443])
      :ok
    end

    test "upload url targets the browser-reachable host, not the cluster service" do
      url = Storage.presigned_upload_url("comments/x/screenshot.png", "image/png")
      uri = URI.parse(url)

      assert uri.scheme == "https"
      assert uri.host == "minio.example.com"
      assert uri.port == 443
      assert uri.path == "/annotate/comments/x/screenshot.png"
      refute url =~ "svc.cluster.local"
      assert URI.decode_query(uri.query)["X-Amz-SignedHeaders"] =~ "host"
    end

    test "download url targets the public host" do
      uri = URI.parse(Storage.presigned_download_url("comments/x/screenshot.png"))
      assert uri.host == "minio.example.com"
      assert uri.scheme == "https"
    end

    test "public_origin is the public endpoint origin" do
      assert Storage.public_origin() == "https://minio.example.com"
    end
  end

  describe "without a public endpoint" do
    test "falls back to the internal endpoint and keeps a well-formed url" do
      put_storage([])
      url = Storage.presigned_upload_url("k.png", "image/png")
      uri = URI.parse(url)

      assert uri.scheme == "http"
      assert uri.host == "minio-service.infra.svc.cluster.local"
      assert uri.port == 9000
      refute url =~ "http://http"
      assert Storage.public_origin() == "http://minio-service.infra.svc.cluster.local:9000"
    end
  end
end

defmodule Annotate.Storage.EndpointTest do
  use ExUnit.Case, async: true

  alias Annotate.Storage.Endpoint

  test "full URL (the deployed S3_ENDPOINT shape) splits into scheme/host/port" do
    assert Endpoint.parse("http://minio-service.infra.svc.cluster.local:9000", "https://") ==
             [scheme: "http://", host: "minio-service.infra.svc.cluster.local", port: 9000]
  end

  test "https URL without port defaults to 443" do
    assert Endpoint.parse("https://minio.noizu.com", "http://") ==
             [scheme: "https://", host: "minio.noizu.com", port: 443]
  end

  test "bare host:port takes the default scheme" do
    assert Endpoint.parse("minio-service.infra.svc.cluster.local:9000", "http://") ==
             [scheme: "http://", host: "minio-service.infra.svc.cluster.local", port: 9000]
  end

  test "nil / blank yield no overrides" do
    assert Endpoint.parse(nil, "https://") == []
    assert Endpoint.parse("  ", "https://") == []
  end

  test "a parsed full URL presigns a well-formed url (regression: http://http:%3A//)" do
    original = Application.get_env(:annotate, Annotate.Storage)
    on_exit(fn -> Application.put_env(:annotate, Annotate.Storage, original) end)

    Application.put_env(
      :annotate,
      Annotate.Storage,
      [bucket: "annotate", region: "us-east-1", access_key_id: "k", secret_access_key: "s"] ++
        Endpoint.parse("http://minio-service.infra.svc.cluster.local:9000", "http://")
    )

    url = Annotate.Storage.presigned_upload_url("a.png", "image/png")

    assert String.starts_with?(
             url,
             "http://minio-service.infra.svc.cluster.local:9000/annotate/a.png?"
           )
  end
end
