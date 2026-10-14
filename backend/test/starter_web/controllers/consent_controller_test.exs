defmodule StarterWeb.ConsentControllerTest do
  use StarterWeb.ConnCase

  describe "cookie consent persistence" do
    test "persists anonymous browser-session preferences", %{conn: conn} do
      browser_session_id = Ecto.UUID.generate()

      conn =
        conn
        |> put_req_header("x-browser-session-id", browser_session_id)
        |> put("/api/v1/consent/cookies", %{
          consent: %{
            version: 1,
            categories: %{
              necessary: false,
              analytics: true,
              marketing: false,
              preferences: true
            }
          }
        })

      response = json_response(conn, 200)
      assert response["requires_session_tracking"] == false
      assert response["consent"]["categories"]["necessary"] == true
      assert response["consent"]["categories"]["analytics"] == true
      assert response["consent"]["categories"]["preferences"] == true

      conn =
        build_conn()
        |> put_req_header("x-browser-session-id", browser_session_id)
        |> get("/api/v1/consent/cookies")

      response = json_response(conn, 200)
      assert response["consent"]["categories"]["analytics"] == true
      assert response["consent"]["categories"]["necessary"] == true
    end

    test "persists preferences against the authenticated user", %{conn: conn} do
      %{access_token: token} = setup_user_and_token()

      conn =
        conn
        |> authenticated_conn(token)
        |> put_req_header("x-browser-session-id", Ecto.UUID.generate())
        |> put("/api/v1/consent/cookies", %{
          consent: %{
            version: 1,
            categories: %{analytics: false, marketing: true, preferences: false}
          }
        })

      assert json_response(conn, 200)["consent"]["categories"]["marketing"] == true

      conn =
        build_conn()
        |> authenticated_conn(token)
        |> put_req_header("x-browser-session-id", Ecto.UUID.generate())
        |> get("/api/v1/consent/cookies")

      response = json_response(conn, 200)
      assert response["consent"]["categories"]["marketing"] == true
      assert response["consent"]["categories"]["necessary"] == true
    end
  end
end
