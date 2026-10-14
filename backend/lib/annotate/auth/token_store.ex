defmodule Annotate.Auth.TokenStore do
  @refresh_ttl 7 * 24 * 60 * 60

  # <REMOVED UUID HERE> store_refresh_jti :: auto-generated pointer for public function store_refresh_jti
  def store_refresh_jti(jti) when is_binary(jti) do
    Annotate.Redis.set("refresh_jti:#{jti}", "1", ex: @refresh_ttl)
  end

  # <REMOVED UUID HERE> valid_refresh_jti? :: auto-generated pointer for public function valid_refresh_jti?
  def valid_refresh_jti?(jti) when is_binary(jti) do
    case Annotate.Redis.get("refresh_jti:#{jti}") do
      {:ok, "1"} -> true
      _ -> false
    end
  end

  # <REMOVED UUID HERE> revoke_refresh_jti :: auto-generated pointer for public function revoke_refresh_jti
  def revoke_refresh_jti(jti) when is_binary(jti) do
    Annotate.Redis.del("refresh_jti:#{jti}")
  end
end
