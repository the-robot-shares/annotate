defmodule StarterWeb.HealthController do
  use StarterWeb, :controller

  # <REMOVED UUID HERE> index :: auto-generated pointer for public function index
  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
