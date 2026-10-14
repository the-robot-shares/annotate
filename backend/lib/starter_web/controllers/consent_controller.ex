defmodule StarterWeb.ConsentController do
  use StarterWeb, :controller

  alias Starter.Schema.CookieConsent
  import Ecto.Query

  @consent_version 1
  @default_categories %{
    "necessary" => true,
    "analytics" => false,
    "marketing" => false,
    "preferences" => false
  }

  # <REMOVED UUID HERE> show :: auto-generated pointer for public function show
  def show(conn, _params) do
    {user_id, browser_session_id} = consent_identity(conn)

    case find_consent(user_id, browser_session_id) do
      nil ->
        json(conn, %{consent: nil})

      consent ->
        json(conn, %{consent: serialize(consent)})
    end
  end

  # <REMOVED UUID HERE> update :: auto-generated pointer for public function update
  def update(conn, %{"consent" => params}) do
    {user_id, browser_session_id} = consent_identity(conn)

    if is_nil(user_id) && is_nil(browser_session_id) do
      conn |> put_status(:bad_request) |> json(%{error: "browser session id required"})
    else
      existing = find_consent(user_id, browser_session_id)
      categories = normalize_categories(params["categories"] || params)
      now = DateTime.utc_now()

      attrs = %{
        user_id: user_id,
        browser_session_id: if(user_id, do: nil, else: browser_session_id),
        version: Map.get(params, "version", @consent_version),
        categories: categories,
        required_session_allowed: true,
        accepted_at: (existing && existing.accepted_at) || now,
        updated_choice_at: now
      }

      changeset =
        (existing || %CookieConsent{})
        |> CookieConsent.changeset(attrs)

      case Starter.Repo.insert_or_update(changeset) do
        {:ok, consent} ->
          json(conn, %{
            consent: serialize(consent),
            requires_session_tracking: false
          })

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  def update(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "consent params required"})
  end

  defp consent_identity(conn) do
    {current_user_id(conn), browser_session_id(conn)}
  end

  defp current_user_id(conn) do
    with ["Bearer " <> token] <- Plug.Conn.get_req_header(conn, "authorization"),
         {:ok, claims} <- Starter.Guardian.decode_and_verify(token),
         {:ok, session} <- Starter.Guardian.resource_from_claims(claims) do
      case session.user do
        {:ref, _, id} -> id
        %{id: id} -> id
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  defp browser_session_id(conn) do
    case Plug.Conn.get_req_header(conn, "x-browser-session-id") do
      [id | _] ->
        case Ecto.UUID.cast(id) do
          {:ok, uuid} -> uuid
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp find_consent(user_id, browser_session_id) when not is_nil(user_id) do
    Starter.Repo.one(from c in CookieConsent, where: c.user_id == ^user_id, limit: 1) ||
      find_consent(nil, browser_session_id)
  end

  defp find_consent(nil, browser_session_id) when not is_nil(browser_session_id) do
    Starter.Repo.one(
      from c in CookieConsent,
        where: is_nil(c.user_id) and c.browser_session_id == ^browser_session_id,
        limit: 1
    )
  end

  defp find_consent(_, _), do: nil

  defp normalize_categories(categories) when is_map(categories) do
    Map.merge(@default_categories, %{
      "necessary" => true,
      "analytics" => Map.get(categories, "analytics", false) == true,
      "marketing" => Map.get(categories, "marketing", false) == true,
      "preferences" => Map.get(categories, "preferences", false) == true
    })
  end

  defp normalize_categories(_), do: @default_categories

  defp serialize(consent) do
    %{
      version: consent.version,
      categories: normalize_categories(consent.categories),
      accepted_at: consent.accepted_at,
      updated_at: consent.updated_choice_at,
      requires_session_tracking: false
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
