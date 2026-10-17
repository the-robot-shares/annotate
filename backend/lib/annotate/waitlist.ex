defmodule Annotate.Waitlist do
  @moduledoc """
  Landing-page waitlist for the features that are not shipped yet (MCP agent
  tools, ticket integrations). One row per (email, interest); re-submitting
  the same pair is a no-op. No confirmation email is sent.
  """

  alias Annotate.Repo
  alias Annotate.Schema.Annotate.WaitlistSignup

  # The only interests the form offers; anything else is rejected. `plan-*`
  # and `agent-addon` power the pricing/dashboard waitlists (full plans and
  # the coming-soon agent add-on — see Annotate.Billing).
  @interests ~w(mcp robot-plans jira notion clickup asana agent-addon
                plan-start plan-standard plan-team)

  # Pragmatic address shape check: one @, no spaces, a dotted domain.
  @email_re ~r/^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/

  def interests, do: @interests

  @doc """
  Validates and records a signup. `params` is the raw request map
  (`"email"`, `"interests"`, honeypot `"website"`).

  Returns `{:ok, n}` (n rows newly inserted; 0 when the honeypot tripped or
  every pair already existed) or `{:error, :invalid_email | :no_interest}`.
  A filled honeypot returns `{:ok, 0}` without touching the database, so
  bots see the same response as a real signup.
  """
  def signup(params) when is_map(params) do
    email = params |> Map.get("email") |> normalize_email()
    interests = params |> Map.get("interests") |> normalize_interests()

    cond do
      honeypot?(params) -> {:ok, 0}
      not valid_email?(email) -> {:error, :invalid_email}
      interests == [] -> {:error, :no_interest}
      true -> insert(email, interests)
    end
  end

  def valid_email?(email) when is_binary(email),
    do: byte_size(email) <= 254 and Regex.match?(@email_re, email)

  def valid_email?(_), do: false

  defp honeypot?(params) do
    case Map.get(params, "website") do
      v when is_binary(v) -> String.trim(v) != ""
      nil -> false
      _ -> true
    end
  end

  defp normalize_email(v) when is_binary(v), do: v |> String.trim() |> String.downcase()
  defp normalize_email(_), do: nil

  defp normalize_interests(v) when is_binary(v), do: normalize_interests([v])

  defp normalize_interests(v) when is_list(v) do
    v
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 in @interests))
    |> Enum.uniq()
  end

  defp normalize_interests(_), do: []

  defp insert(email, interests) do
    now = DateTime.utc_now()

    rows =
      Enum.map(interests, fn i ->
        %{email: email, interest: i, source: "landing", created_at: now}
      end)

    {n, _} =
      Repo.insert_all(WaitlistSignup, rows,
        on_conflict: :nothing,
        conflict_target: [:email, :interest]
      )

    {:ok, n}
  end
end
