defmodule AnnotateWeb.Hologram.Pages.SitemapPage do
  use Hologram.Page

  alias Hologram.UI.Link
  alias AnnotateWeb.Hologram.Layouts.MainLayout

  alias AnnotateWeb.Hologram.Pages.{
    AdminOrgsPage,
    AdminUsersPage,
    AppHomePage,
    ForgotPasswordPage,
    HomePage,
    LoginPage,
    ProfilePage,
    SignupPage,
    StyleGuidePage,
    TailwindPlusPage
  }

  route "/sitemap"
  layout MainLayout, page_title: "Site Map"

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, _server), do: put_state(component, :ok, true)

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="content">
      <h1 class="sg-page-title">Site Map</h1>
      <ul>
        <li><Link to={HomePage}>Home</Link></li>
        <li><Link to={LoginPage}>Log In</Link></li>
        <li><Link to={SignupPage}>Sign Up</Link></li>
        <li><Link to={ForgotPasswordPage}>Forgot Password</Link></li>
        <li><Link to={StyleGuidePage}>Style Guide</Link></li>
        <li><Link to={TailwindPlusPage}>Tailwind Plus</Link></li>
        <li><Link to={AppHomePage}>App Home</Link></li>
        <li><Link to={ProfilePage}>Profile</Link></li>
        <li><Link to={AdminUsersPage}>Admin · Users</Link></li>
        <li><Link to={AdminOrgsPage}>Admin · Organizations</Link></li>
        <li><a href="/app/:org_id/members">Org Members</a> (parametrized)</li>
      </ul>
    </div>
    """
  end
end
