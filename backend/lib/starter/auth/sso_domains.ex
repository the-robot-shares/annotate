defmodule Starter.Auth.SSODomains do
  @moduledoc """
  Normalizes per-domain SSO policy.

  `:sso_domains` is the legacy/public availability map:

      %{"example.com" => ["oidc", "google"]}

  `:sso_auto_approve_domains` is an optional list of domains whose new SSO
  registrations should be active immediately. All other SSO registrations are
  created pending manual approval unless an invite later activates them.
  """

  # <REMOVED UUID HERE> policies :: auto-generated pointer for public function policies
  def policies do
    explicit = Application.get_env(:starter, :sso_domain_policies, %{})
    legacy = Application.get_env(:starter, :sso_domains, %{})
    auto_approve = Application.get_env(:starter, :sso_auto_approve_domains, [])

    case explicit do
      value when is_map(value) and map_size(value) > 0 ->
        normalize_explicit_policies(value)

      _ ->
        build_policies(legacy, auto_approve)
    end
  end

  # <REMOVED UUID HERE> providers_map :: auto-generated pointer for public function providers_map
  def providers_map do
    policies()
    |> Enum.into(%{}, fn {domain, policy} -> {domain, policy.providers} end)
  end

  # <REMOVED UUID HERE> public_policies :: auto-generated pointer for public function public_policies
  def public_policies do
    policies()
    |> Enum.into(%{}, fn {domain, policy} ->
      {domain, %{providers: policy.providers, auto_approve: policy.auto_approve}}
    end)
  end

  # <REMOVED UUID HERE> sso_available? :: auto-generated pointer for public function sso_available?
  def sso_available?(email_or_domain, provider) do
    provider = provider_name(provider)

    case policy_for(email_or_domain) do
      %{providers: providers} -> provider in providers
      nil -> false
    end
  end

  # <REMOVED UUID HERE> auto_approve? :: auto-generated pointer for public function auto_approve?
  def auto_approve?(email_or_domain, provider) do
    provider = provider_name(provider)

    case policy_for(email_or_domain) do
      %{providers: providers, auto_approve: true} -> provider in providers
      _ -> false
    end
  end

  @doc """
  True when the email's domain policy is auto-approve, whatever the provider.
  Password signups on such a domain need only a confirmed email
  (`Starter.Auth.InviteGate.signup_status/3`).
  """
  def auto_approve_domain?(email_or_domain) do
    listed =
      Application.get_env(:starter, :sso_auto_approve_domains, [])
      |> normalize_domain_list()

    domain = normalize_domain(email_or_domain)

    match?(%{auto_approve: true}, policy_for(email_or_domain)) or
      (not is_nil(domain) and (domain in listed or "*" in listed))
  end

  # <REMOVED UUID HERE> registration_status :: auto-generated pointer for public function registration_status
  def registration_status(email_or_domain, provider) do
    if auto_approve?(email_or_domain, provider), do: :active, else: :pending
  end

  # <REMOVED UUID HERE> policy_for :: auto-generated pointer for public function policy_for
  def policy_for(email_or_domain) do
    domain = normalize_domain(email_or_domain)
    if domain, do: Map.get(policies(), domain)
  end

  # <REMOVED UUID HERE> build_policies :: auto-generated pointer for public function build_policies
  def build_policies(domains, auto_approve_domains) when is_map(domains) do
    auto_approve_set =
      auto_approve_domains
      |> normalize_domain_list()
      |> MapSet.new()

    domains
    |> Enum.reduce(%{}, fn {domain, providers}, acc ->
      domain = normalize_domain(domain)
      providers = normalize_providers(providers)

      if domain && providers != [] do
        Map.put(acc, domain, %{
          providers: providers,
          auto_approve:
            MapSet.member?(auto_approve_set, "*") || MapSet.member?(auto_approve_set, domain)
        })
      else
        acc
      end
    end)
  end

  def build_policies(_, _), do: %{}

  defp normalize_explicit_policies(policies) do
    policies
    |> Enum.reduce(%{}, fn {domain, policy}, acc ->
      domain = normalize_domain(domain)
      policy = normalize_policy(policy)

      if domain && policy.providers != [] do
        Map.put(acc, domain, policy)
      else
        acc
      end
    end)
  end

  defp normalize_policy(providers) when is_list(providers),
    do: %{providers: normalize_providers(providers), auto_approve: false}

  defp normalize_policy(policy) when is_map(policy) do
    providers =
      Map.get(policy, :providers) ||
        Map.get(policy, "providers") ||
        Map.get(policy, :sso_providers) ||
        Map.get(policy, "sso_providers") ||
        []

    auto_approve =
      Map.get(policy, :auto_approve) ||
        Map.get(policy, "auto_approve") ||
        Map.get(policy, :autoApprove) ||
        Map.get(policy, "autoApprove") ||
        false

    %{providers: normalize_providers(providers), auto_approve: truthy?(auto_approve)}
  end

  defp normalize_policy(_), do: %{providers: [], auto_approve: false}

  defp normalize_providers(providers) when is_binary(providers) do
    providers
    |> String.split(",", trim: true)
    |> normalize_providers()
  end

  defp normalize_providers(providers) when is_list(providers) do
    providers
    |> Enum.map(&provider_name/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_providers(_), do: []

  defp normalize_domain_list(value) when is_binary(value) do
    value
    |> String.split(~r/[,\s;]+/, trim: true)
    |> Enum.map(&normalize_domain/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_domain_list(value) when is_list(value) do
    value
    |> Enum.map(&normalize_domain/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_domain_list(%MapSet{} = value), do: normalize_domain_list(MapSet.to_list(value))
  defp normalize_domain_list(_), do: []

  defp normalize_domain(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_domain()

  defp normalize_domain(value) when is_binary(value) do
    value = value |> String.trim() |> String.downcase()

    cond do
      value == "" ->
        nil

      String.contains?(value, "@") ->
        value |> String.split("@") |> List.last() |> normalize_domain()

      true ->
        value
    end
  end

  defp normalize_domain(_), do: nil

  defp provider_name(value) when is_atom(value), do: Atom.to_string(value)
  defp provider_name(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp provider_name(_), do: ""

  defp truthy?(value) when value in [true, "true", "TRUE", "1", 1, "yes", "YES", "on", "ON"],
    do: true

  defp truthy?(_), do: false
end
