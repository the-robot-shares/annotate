defmodule Annotate.FeatureFlags do
  # <REMOVED UUID HERE> enabled? :: auto-generated pointer for public function enabled?
  def enabled?(flag) when is_atom(flag) do
    flags = Application.get_env(:annotate, :feature_flags, %{})
    Map.get(flags, flag, false)
  end

  @doc """
  Past invite-only: when on, `Annotate.Auth.InviteGate` stops holding gated
  accounts and every signup is `:active`.
  """
  def general_release?, do: enabled?(:general_release)

  # <REMOVED UUID HERE> all :: auto-generated pointer for public function all
  def all do
    Application.get_env(:annotate, :feature_flags, %{})
    |> Enum.filter(fn {_k, v} -> v end)
    |> Enum.map(fn {k, _v} -> Atom.to_string(k) end)
  end
end
