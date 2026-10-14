defmodule Annotate.Auth.SSOCode do
  @ttl_seconds 60

  # <REMOVED UUID HERE> create :: auto-generated pointer for public function create
  def create(session_id) do
    code = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    {:ok, _} = Annotate.Redis.set("sso_code:#{code}", to_string(session_id), ex: @ttl_seconds)
    {:ok, code}
  end

  # <REMOVED UUID HERE> exchange :: auto-generated pointer for public function exchange
  def exchange(code) do
    key = Annotate.Redis.prefix("sso_code:#{code}")

    case Annotate.Redis.command(["GETDEL", key]) do
      {:ok, nil} -> {:error, :invalid_code}
      {:ok, session_id} -> {:ok, session_id}
    end
  end
end
