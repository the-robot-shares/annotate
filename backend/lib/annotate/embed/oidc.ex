defmodule Annotate.Embed.OIDC do
  @moduledoc """
  Thin seam over `OpenIDConnect` for the embed auth broker.

  Indirection exists for tests: `Application.put_env(:annotate, :oidc_impl,
  FakeModule)` swaps the implementation so the popup flow can be exercised
  without a live IdP. Production default is `OpenIDConnect`.

  Provider config reuses the scaffold's `:openid_connect, :providers, :default`
  (OIDC_ISSUER / OIDC_CLIENT_ID / OIDC_CLIENT_SECRET env wiring in
  runtime.exs). The embed flow overrides `redirect_uri` with
  `EMBED_OIDC_REDIRECT_URI` (default `https://<host>/embed/callback`).
  """

  def impl, do: Application.get_env(:annotate, :oidc_impl, OpenIDConnect)

  def config do
    base =
      :openid_connect
      |> Application.fetch_env!(:providers)
      |> Keyword.fetch!(:default)
      |> Map.new()

    Map.put(base, :redirect_uri, embed_redirect_uri(base))
  end

  def embed_redirect_uri(base \\ nil) do
    Application.get_env(:annotate, :embed, [])[:redirect_uri] ||
      (base && base[:redirect_uri]) ||
      "http://localhost:4002/embed/callback"
  end

  def configured? do
    match?({:ok, _}, Application.fetch_env(:openid_connect, :providers)) and
      Keyword.has_key?(Application.get_env(:openid_connect, :providers, []), :default)
  end

  def authorization_uri(params \\ %{}) do
    config = config()

    # OpenIDConnect returns %URI{} (older builds: a string); tests may fake an
    # {:ok, _}. Normalize to {:ok, uri_string} for the controller.
    # OpenIDConnect.authorization_uri/3 merges `params` into the authorize
    # query with Map.merge/2 — atom-keyed map per its @spec.
    case impl().authorization_uri(config, config.redirect_uri, params) do
      {:ok, uri} -> {:ok, uri}
      %URI{} = uri -> {:ok, URI.to_string(uri)}
      uri when is_binary(uri) -> {:ok, uri}
      other -> {:error, other}
    end
  end

  def fetch_tokens(%{"code" => code, "redirect_uri" => redirect_uri}) do
    # OpenIDConnect.fetch_tokens/2 takes a MAP of atom-keyed token-request
    # params (merged into the POST form via Map.merge/2). A keyword list
    # raises BadMapError mid-exchange — that was the prod 500 on
    # /embed/callback (2026-10-16): the crash happened AFTER the session
    # state/nonce checks, so the popup died with an opaque 500 at the code
    # exchange even though the cookie flow was healthy.
    impl().fetch_tokens(config(), %{code: code, redirect_uri: redirect_uri})
  end

  def verify(id_token) do
    impl().verify(config(), id_token)
  end
end
