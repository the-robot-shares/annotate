defmodule Annotate.Auth.ServiceKey do
  @moduledoc """
  Site service keys — bearer material for the host-assert flow.

  A site's service key is a random 32-byte url64 string, shown ONCE at site
  creation (`mix annotate.site.create`). Hosts sign short-lived HS256 JWTs
  with it (`POST /api/v1/sites/:site/token/assert`), so the server must be
  able to RECOVER the key to verify the HMAC — a one-way hash is not enough.

  Design choice (documented in docs/EMBED-AUTH.md): we store BOTH
  `sites.service_key_hash` (sha256 hex — cheap existence/lookup checks) AND
  `sites.service_key_encrypted` — the key sealed with AES-256-GCM under a key
  derived from `ANNOTATE_KEY_ENC_SECRET`. Plaintext never touches the
  database; the encrypted column is decryptable only at runtime with the
  deployment secret, trading "hash-only" for the ability to verify
  host-asserted identity. Leak of the DB alone does not expose service keys.
  """

  @aad "annotate.service-key.v1"

  def enc_secret do
    case Application.get_env(:annotate, __MODULE__, [])[:enc_secret] do
      nil -> raise "Annotate.Auth.ServiceKey enc_secret not configured (ANNOTATE_KEY_ENC_SECRET)"
      secret -> secret
    end
  end

  @doc "Generates a new service key (43-char url64). Shown once."
  def generate, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  @doc "sha256 hex digest — stored in `sites.service_key_hash`."
  def hash(key) when is_binary(key), do: Base.encode16(:crypto.hash(:sha256, key), case: :lower)

  @doc "AES-256-GCM seal; returns url64 `iv.ciphertext.tag`."
  def encrypt(plain) when is_binary(plain) do
    iv = :crypto.strong_rand_bytes(12)

    {cipher, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, derive_key(), iv, plain, @aad, true)

    Enum.map_join([iv, cipher, tag], ".", &Base.url_encode64(&1, padding: false))
  end

  @doc "Opens a value from `encrypt/1`; `{:ok, plain}` or `:error`."
  def decrypt(sealed) when is_binary(sealed) do
    with [iv, cipher, tag] <- String.split(sealed, "."),
         {:ok, iv} <- url_decode(iv),
         {:ok, cipher} <- url_decode(cipher),
         {:ok, tag} <- url_decode(tag) do
      try do
        plain =
          :crypto.crypto_one_time_aead(:aes_256_gcm, derive_key(), iv, cipher, @aad, tag, false)

        {:ok, plain}
      rescue
        _ -> :error
      end
    else
      _ -> :error
    end
  end

  def decrypt(nil), do: :error

  defp url_decode(s) do
    case Base.url_decode64(s, padding: false) do
      {:ok, bin} -> {:ok, bin}
      :error -> :error
    end
  end

  defp derive_key, do: :crypto.hash(:sha256, enc_secret())
end
