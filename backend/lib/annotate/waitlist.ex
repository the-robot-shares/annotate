defmodule Annotate.Waitlist do
  @moduledoc """
  Landing-page waitlist for the features that are not shipped yet (MCP agent
  tools, ticket integrations). One row per (email, interest); re-submitting
  the same pair is a no-op. No confirmation email is sent.
  """

  alias Annotate.Repo
  alias Annotate.Schema.Annotate.WaitlistSignup

  # The interests the form offered historically plus the dashboard waitlists;
  # anything else is rejected. `plan-*` and `agent-addon` power the
  # pricing/dashboard waitlists (see Annotate.Billing). The landing form no
  # longer asks about interests — it records a single `waitlist` row with
  # about/use_case text instead (feedback a90465e3, 2026-10-18).
  @interests ~w(waitlist mcp robot-plans jira notion clickup asana agent-addon
                plan-start plan-standard plan-team)

  # Pragmatic address shape check: one @, no spaces, a dotted domain.
  @email_re ~r/^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/

  def interests, do: @interests

  @doc """
  Validates and records a signup.

  Two shapes:

    * the landing "for you" form — `params` carries `"email"`, `"about"`
      (required), optional `"use_case"`, honeypot `"website"`; one row with
      interest `"waitlist"` and the text stored on it;
    * the dashboard plan/agent waitlists — `params` carries `"interests"`;
      one row per (email, interest) as before.

  Returns `{:ok, n}` (n rows newly inserted; 0 when the honeypot tripped or
  every row already existed) or `{:error, :invalid_email | :no_interest |
  :no_about}`. A filled honeypot returns `{:ok, 0}` without touching the
  database, so bots see the same response as a real signup.
  """
  def signup(params) when is_map(params) do
    email = params |> Map.get("email") |> normalize_email()

    if Map.has_key?(params, "interests") do
      interests = params |> Map.get("interests") |> normalize_interests()

      cond do
        honeypot?(params) -> {:ok, 0}
        not valid_email?(email) -> {:error, :invalid_email}
        interests == [] -> {:error, :no_interest}
        true -> insert(email, interests, nil, nil)
      end
    else
      about = params |> Map.get("about") |> normalize_text()
      use_case = params |> Map.get("use_case") |> normalize_text()

      cond do
        honeypot?(params) -> {:ok, 0}
        not valid_email?(email) -> {:error, :invalid_email}
        about == nil or about == "" -> {:error, :no_about}
        true -> insert(email, ["waitlist"], about, use_case)
      end
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

  defp normalize_text(v) when is_binary(v) do
    v |> String.trim() |> String.slice(0, 500)
  end

  defp normalize_text(_), do: nil

  defp normalize_interests(v) when is_binary(v), do: normalize_interests([v])

  defp normalize_interests(v) when is_list(v) do
    v
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 in @interests))
    |> Enum.uniq()
  end

  defp normalize_interests(_), do: []

  defp insert(email, interests, about, use_case) do
    now = DateTime.utc_now()

    rows =
      Enum.map(interests, fn i ->
        base = %{email: email, interest: i, source: "landing", created_at: now}

        if i == "waitlist",
          do: Map.merge(base, %{about: about, use_case: use_case}),
          else: base
      end)

    {n, _} =
      Repo.insert_all(WaitlistSignup, rows,
        on_conflict: :nothing,
        conflict_target: [:email, :interest]
      )

    {:ok, n}
  end
end
