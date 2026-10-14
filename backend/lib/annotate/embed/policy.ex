defmodule Annotate.Embed.Policy do
  @moduledoc """
  Site comment_policy enforcement for identities acquired via the auth broker.

  - `required_groups` ([] = any): any-of match against the id token `groups`
    claim (Authentik's group mappings).
  - `allowed_email_domains` ([] = any): email domain must be listed.
  - `host_identity` (bool): declarative — enables the host-assert flow; not
    enforced on the OIDC popup path.
  """

  @type policy :: map()
  @type claims :: map()

  @spec check(claims, policy) :: :ok | {:error, :group_not_allowed | :email_domain_not_allowed}
  def check(claims, policy) do
    with :ok <- check_groups(claims, policy) do
      check_email_domain(claims, policy)
    end
  end

  defp check_groups(claims, policy) do
    required = normalize_list(policy["required_groups"])
    groups = normalize_list(claims["groups"])

    cond do
      required == [] -> :ok
      Enum.any?(required, &(&1 in groups)) -> :ok
      true -> {:error, :group_not_allowed}
    end
  end

  defp check_email_domain(claims, policy) do
    allowed = normalize_list(policy["allowed_email_domains"])
    domain = email_domain(claims["email"])

    cond do
      allowed == [] -> :ok
      domain == nil -> {:error, :email_domain_not_allowed}
      domain in allowed -> :ok
      true -> {:error, :email_domain_not_allowed}
    end
  end

  defp email_domain(email) when is_binary(email) do
    case String.split(String.trim(email), "@") do
      [_, domain] -> String.downcase(domain)
      _ -> nil
    end
  end

  defp email_domain(_), do: nil

  defp normalize_list(nil), do: []
  defp normalize_list(list) when is_list(list), do: list |> Enum.filter(&is_binary/1)
  defp normalize_list(_), do: []
end
