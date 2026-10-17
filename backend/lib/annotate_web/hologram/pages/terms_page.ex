defmodule AnnotateWeb.Hologram.Pages.TermsPage do
  @moduledoc """
  `/terms` — Terms of Service. Text lives in the `legal_forms` component
  (Components/legal-forms); this page supplies `AnnotateWeb.Legal` config. As-is, no SLA, no data guarantees. Operator and
  contact follow house prior art (Noizu Labs, Inc.; keith.brings@noizu.com).
  No governing-law clause: no jurisdiction has been specified.
  """

  use Hologram.Page

  require LegalForms.Hologram

  alias AnnotateWeb.Hologram.Layouts.LegalLayout

  route "/terms"

  layout LegalLayout,
    page_title: "Terms of Service — annotate",
    description:
      "annotate is provided as is, with no SLA and no guarantee of data. Read the terms for using the comment widget and dashboard.",
    path: "/terms"

  def init(_params, component, _server), do: component

  def template do
    LegalForms.Hologram.template(:terms, AnnotateWeb.Legal.config(:terms),
      before:
        ~s(<article class="nd-legal__inner" data-cy="terms-page"><p class="nd-section__label">Legal</p>),
      after: "</article>",
      meta_class: "nd-legal__meta"
    )
  end
end
