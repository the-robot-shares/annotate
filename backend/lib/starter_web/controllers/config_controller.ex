defmodule StarterWeb.ConfigController do
  use StarterWeb, :controller

  # <REMOVED UUID HERE> features :: auto-generated pointer for public function features
  def features(conn, _params) do
    flags = Starter.FeatureFlags.all()
    conn |> put_status(:ok) |> json(%{features: flags})
  end
end
