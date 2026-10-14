defmodule AnnotateWeb.ConfigController do
  use AnnotateWeb, :controller

  # <REMOVED UUID HERE> features :: auto-generated pointer for public function features
  def features(conn, _params) do
    flags = Annotate.FeatureFlags.all()
    conn |> put_status(:ok) |> json(%{features: flags})
  end
end
