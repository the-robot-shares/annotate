defmodule AnnotateWeb.Hologram.Pages.TermsPage do
  @moduledoc """
  `/terms` — Terms of Service. As-is, no SLA, no data guarantees. Operator and
  contact follow house prior art (Noizu Labs, Inc.; keith.brings@noizu.com).
  No governing-law clause: no jurisdiction has been specified.
  """

  use Hologram.Page

  alias AnnotateWeb.Hologram.Layouts.LegalLayout

  route "/terms"

  layout LegalLayout,
    page_title: "Terms of Service — annotate",
    description:
      "annotate is provided as is, with no SLA and no guarantee of data. Read the terms for using the comment widget and dashboard.",
    path: "/terms"

  def init(_params, component, _server), do: component

  def template do
    ~HOLO"""
    <article class="nd-legal__inner" data-cy="terms-page">
      <p class="nd-section__label">Legal</p>
      <h1>Terms of Service</h1>
      <p class="nd-legal__meta">Last updated: 2026-10-17</p>

      <p>
        These terms apply to annotate (the comment widget, the dashboard and the API, together
        "the service"), operated by Noizu Labs, Inc. ("we", "us"). By using the service you agree
        to them and to our <a href="/privacy">Privacy Policy</a>. If you do not agree, do not use it.
      </p>

      <h2>AS IS and AS AVAILABLE</h2>
      <p>
        The service is provided "AS IS" and "AS AVAILABLE", without warranties of any kind, express
        or implied, including merchantability, fitness for a particular purpose, accuracy, security,
        and non-infringement. We do not promise that it will be uninterrupted, error-free or secure.
      </p>

      <h2>No SLA</h2>
      <p>
        There is no service level agreement and no uptime guarantee. The service may be slow, down,
        or broken at any time, for any length of time, with no compensation, credit or refund.
      </p>

      <h2>No guarantee of data, and data loss</h2>
      <p>
        We do not guarantee that your data (comments, attachments, screenshots, sites, settings, keys
        or accounts) will be durable, retained, backed up or recoverable. Data loss can and may happen:
        data may be lost, corrupted, exposed or deleted at any time, with or without a reason or notice.
        You are responsible for keeping your own copies of anything you care about. Do not use annotate as
        your only record of anything important.
      </p>

      <h2>Changes, suspension and termination of the service</h2>
      <p>
        We may change, limit, suspend or discontinue all or part of the service (including features, limits,
        pricing, or the whole product) at any time, without notice and without liability to you.
      </p>

      <h2>Your account</h2>
      <p>
        You sign in with GitHub and are responsible for what happens under your account and for
        keeping your keys and sign-in secure. You must be at least 13 and able to form a binding
        agreement. We may suspend or terminate your account, or remove your sites and content, at any
        time, for any reason (including a breach of these terms), without notice. You may stop using the
        service and ask us to delete your account at any time. Sections that by nature should survive
        termination do survive it.
      </p>

      <h2>Site owners</h2>
      <p>
        If you put annotate on a website, you are responsible for that site, its content, and for your
        visitors' comments and personal data. That includes telling your visitors the widget is present,
        having any consent or legal basis you need, responding to their requests, and moderating comments.
        We act as your processor for your visitors' comments, as described in the Privacy Policy.
      </p>

      <h2>Acceptable use</h2>
      <p>You agree not to use the service to:</p>
      <ul>
        <li>post or store anything unlawful, infringing, harassing, hateful or otherwise abusive;</li>
        <li>send spam or unsolicited promotion;</li>
        <li>upload malware or anything meant to harm other people's systems or browsers;</li>
        <li>probe, scrape or overload the service, or try to bypass or break its security, rate limits, origin checks or access controls;</li>
        <li>impersonate others or access data that is not yours;</li>
        <li>or otherwise break the law or someone else's rights.</li>
      </ul>
      <p>We may remove content and block access if we think these rules are broken.</p>

      <h2>Your content</h2>
      <p>
        You keep ownership of what you post. You give us the right to host, copy, display and
        transmit it as needed to run the service. You promise you have the rights to do so.
      </p>

      <h2>Limitation of liability</h2>
      <p>
        To the maximum extent permitted by law, Noizu Labs, Inc. and the people behind it will not be
        liable for any indirect, incidental, special, consequential or punitive damages, or for lost data,
        profits, revenue or goodwill, arising from the service, even if we were warned of the possibility.
        Our total liability for any claim is limited to the amount you paid us for the service in the 12
        months before the claim, which for a free service is $0. Some places do not allow some of these limits,
        in which case they apply as far as the law allows.
      </p>

      <h2>Indemnity</h2>
      <p>
        You will defend and indemnify Noizu Labs, Inc. against claims, damages and costs (including
        reasonable legal fees) arising from your content, your site, your visitors' content, your use of
        the service, or your breach of these terms.
      </p>

      <h2>Changes to these terms</h2>
      <p>
        We may update these terms at any time. The date above shows the latest version, and continued
        use after a change means you accept it.
      </p>

      <h2>Contact</h2>
      <p>
        Noizu Labs, Inc. &middot; <a href="mailto:keith.brings@noizu.com">keith.brings@noizu.com</a> &middot;
        See also the <a href="/privacy">Privacy Policy</a>.
      </p>
    </article>
    """
  end
end
