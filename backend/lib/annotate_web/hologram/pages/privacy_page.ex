defmodule AnnotateWeb.Hologram.Pages.PrivacyPage do
  @moduledoc """
  `/privacy` — Privacy Policy. Text lives in the `legal_forms` component
  (Components/legal-forms); this page supplies `AnnotateWeb.Legal` config. Grounded in what annotate actually stores
  (docs/PROJ-ARCH.md, docs/ANCHORS.md, docs/THREAT-MODEL.md). Operator and
  contact follow house prior art (Noizu Labs, Inc.; keith.brings@noizu.com).
  """

  use Hologram.Page

  require LegalForms.Hologram
  # Compile-time dependency: editing AnnotateWeb.Legal must recompile this page
  # (a cached _build served stale policy text in CI).
  require AnnotateWeb.Legal

  alias AnnotateWeb.Hologram.Layouts.LegalLayout

  route "/privacy"

  layout LegalLayout,
    page_title: "Privacy Policy — annotate",
    description:
      "What annotate collects when you comment on a page or manage a site, who processes it, how long we keep it, and how to ask for deletion.",
    path: "/privacy"

  def init(_params, component, _server), do: component

  def template do
    LegalForms.Hologram.template(:privacy, AnnotateWeb.Legal.config(:privacy),
      before:
        ~s(<article class="nd-legal__inner" data-cy="privacy-page"><p class="nd-section__label">Legal</p>),
      after: "</article>",
      meta_class: "nd-legal__meta"
    )
  end
end
