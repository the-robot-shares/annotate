defmodule AnnotateWeb.Hologram.Pages.PendingApprovalPage do
  @moduledoc """
  Legacy `/pending-approval` route: the invite interstitial replaced it, so
  old links and bookmarks land on `/auth/invite-required`.
  """
  use Hologram.Page

  alias AnnotateWeb.Hologram.Layouts.MainLayout
  alias AnnotateWeb.Hologram.Pages.InviteRequiredPage

  route "/pending-approval"
  layout MainLayout, page_title: "Invite required"
  middleware :to_interstitial

  def to_interstitial(server, _opts), do: Hologram.Server.put_redirect(server, InviteRequiredPage)

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, _server), do: component

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="content"><p><a href="/auth/invite-required">Continue</a></p></div>
    """
  end
end
