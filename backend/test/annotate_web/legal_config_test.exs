defmodule AnnotateWeb.LegalConfigTest do
  use ExUnit.Case, async: true

  # Text lives in Components/legal-forms; these guard annotate's config of it.
  test "layout meta literals stay in sync with the config" do
    for {doc, mod} <- [
          privacy: AnnotateWeb.Hologram.Pages.PrivacyPage,
          terms: AnnotateWeb.Hologram.Pages.TermsPage
        ] do
      meta = AnnotateWeb.Legal.meta(doc)
      layout_props = Map.new(mod.__layout_props__())
      assert layout_props[:page_title] == meta.page_title
      assert layout_props[:description] == meta.description
    end
  end

  test "rendered text keeps the required legal clauses and no governing-law section" do
    terms = LegalForms.render(:terms, AnnotateWeb.Legal.config(:terms))

    for c <- [
          "AS IS and AS AVAILABLE",
          "No SLA",
          "Data loss can and may happen",
          "Limitation of liability",
          "Indemnity",
          "Acceptable use"
        ],
        do: assert(terms =~ c)

    refute terms =~ "Governing law"
    refute terms =~ "TODO"
  end
end
