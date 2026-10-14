defmodule AnnotateWeb.HealthController do
  use AnnotateWeb, :controller

  # <REMOVED UUID HERE> index :: auto-generated pointer for public function index
  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
