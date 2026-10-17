defmodule AnnotateWeb.Router do
  use AnnotateWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug AnnotateWeb.AuthPipeline
  end

  pipeline :sso_session do
    # 900s, not 300s: this cookie now carries the OIDC `state`/`nonce` pair
    # (see SSOController.oidc_init/2), so its expiry gates how long a login
    # can take, not just how long a redirect can take. 300s is too short for
    # password + a 2FA code typed on a phone - the flow would still complete,
    # but only insecurely, since it fails closed to an opaque `state_mismatch`
    # with no indication it was a timeout rather than an attack. This cookie
    # carries flow state, never credentials, so 900s is not a
    # credential-lifetime decision.
    plug AnnotateWeb.Plugs.SsoSession
    plug :fetch_session
  end

  # GitHub-only deployments (Annotate.Auth.LoginMethods) refuse every other
  # sign-in family at the route, not just in the UI.
  pipeline :password_login do
    plug AnnotateWeb.Plugs.RequireLoginMethod, method: "password"
  end

  pipeline :oidc_login do
    plug AnnotateWeb.Plugs.RequireLoginMethod, method: "oidc"
  end

  pipeline :saml_login do
    plug AnnotateWeb.Plugs.RequireLoginMethod, method: "saml"
  end

  pipeline :oauth_login do
    plug AnnotateWeb.Plugs.RequireLoginMethod, from_param: "provider"
  end

  pipeline :rate_limited_auth do
    plug AnnotateWeb.Plugs.RateLimit, action: :auth
  end

  pipeline :rate_limited_sensitive do
    plug AnnotateWeb.Plugs.RateLimit, action: :auth_sensitive
  end

  # Annotate embed API write budget: per (ip, site), write methods only.
  pipeline :annotate_rate_limited do
    plug AnnotateWeb.Plugs.RateLimit, action: :annotate_write
  end

  # Landing waitlist signups: tight per-IP budget (no site scoping).
  pipeline :waitlist_rate_limited do
    plug AnnotateWeb.Plugs.RateLimit, action: :waitlist
  end

  pipeline :org_viewer do
    plug AnnotateWeb.Plugs.RequireRole, role: "viewer"
  end

  pipeline :org_editor do
    plug AnnotateWeb.Plugs.RequireRole, role: "editor"
  end

  pipeline :org_admin do
    plug AnnotateWeb.Plugs.RequireRole, role: "admin"
  end

  pipeline :org_owner do
    plug AnnotateWeb.Plugs.RequireRole, role: "owner"
  end

  pipeline :admin do
    plug AnnotateWeb.Plugs.RequireAdmin
  end

  # ── Annotate embeddable-comments API ─────────────────────────
  # :optional = anonymous reads allowed when settings.public_read; anonymous
  # POST (guest threads) only when comment_policy.allow_anonymous — otherwise
  # writes require a token like every other write. :required = valid
  # Annotate.Auth.ApiToken mandatory. Binding checks (origin/site claims) live
  # in AnnotateWeb.Plugs.AnnotateAuth.
  pipeline :annotate_auth_optional do
    plug AnnotateWeb.Plugs.AnnotateAuth, mode: :optional
  end

  pipeline :annotate_auth_required do
    plug AnnotateWeb.Plugs.AnnotateAuth, mode: :required
  end

  scope "/", AnnotateWeb do
    pipe_through :api
    get "/health", HealthController, :index
  end

  # Stripe webhook: signature-verified over the RAW body (RawBodyReader);
  # no auth pipeline, no rate limit (Stripe is the caller; retries answer 200).
  scope "/api/v1/billing", AnnotateWeb do
    pipe_through [:api]
    post "/webhook", BillingWebhookController, :create
  end

  # Deliberately NOT under /api/v1: AnnotateCORS denies any browser Origin that
  # is not a registered site origin there, and the landing form is same-origin.
  scope "/", AnnotateWeb do
    pipe_through [:waitlist_rate_limited]
    post "/waitlist", WaitlistController, :create
  end

  scope "/api/v1", AnnotateWeb do
    pipe_through [:api, :password_login, :rate_limited_auth]
    post "/auth/register", AuthController, :register
    post "/auth/login", AuthController, :login
  end

  scope "/api/v1", AnnotateWeb do
    pipe_through [:api, :rate_limited_auth]
    post "/auth/refresh", AuthController, :refresh
    get "/consent/cookies", ConsentController, :show
    put "/consent/cookies", ConsentController, :update
    get "/auth/sso/providers", SSOController, :providers
    post "/auth/sso/exchange", SSOController, :exchange
    get "/invites/lookup", InviteTokenController, :lookup
    get "/config/features", ConfigController, :features
  end

  scope "/api/v1", AnnotateWeb do
    pipe_through [:api, :password_login, :rate_limited_sensitive]
    post "/auth/magic-link", AuthController, :request_magic_link
    post "/auth/magic-link/verify", AuthController, :verify_magic_link
    post "/auth/otp-login", AuthController, :request_otp_login
    post "/auth/otp-login/verify", AuthController, :verify_otp_login
    post "/auth/password-reset", AuthController, :request_password_reset
    post "/auth/password-reset/verify", AuthController, :verify_password_reset
    post "/auth/verify-email/confirm", AuthController, :verify_email
  end

  scope "/api/v1", AnnotateWeb do
    pipe_through [:api, :authenticated]
    get "/auth/me", AuthController, :me
    get "/users/me", UserController, :show
    patch "/users/me", UserController, :update
    post "/users/me/complete-registration", UserController, :complete_registration
    resources "/organizations", OrganizationController, only: [:index, :create, :show]
    post "/media/presign", MediaController, :presign
    post "/media/download", MediaController, :download
    post "/media/register", MediaController, :register
  end

  scope "/api/v1", AnnotateWeb do
    pipe_through [:api, :password_login, :authenticated]
    post "/auth/verify-email", AuthController, :send_verification
  end

  # Redeem an invite as a signed-in user (the /auth/invite-required
  # interstitial and /join for existing accounts). Exempt from the invite gate
  # (AnnotateWeb.Plugs.RequireInvite) and rate-limited: it is a token oracle.
  scope "/api/v1", AnnotateWeb do
    pipe_through [:api, :rate_limited_sensitive, :authenticated]
    post "/invites/redeem", InviteTokenController, :redeem
  end

  scope "/api/v1/organizations/:org_id", AnnotateWeb do
    pipe_through [:api, :authenticated, :org_admin]
    resources "/members", MembershipController, only: [:index, :create, :update, :delete]
    resources "/invites", InviteTokenController, only: [:index, :create, :delete]
    get "/invites/:id/redemptions", InviteTokenController, :redemptions
  end

  scope "/api/v1/admin", AnnotateWeb do
    pipe_through [:api, :authenticated, :admin]
    get "/users", AdminController, :list_users
    get "/users/:id", AdminController, :show_user
    post "/users/:id/approve", AdminController, :approve_user
    get "/organizations", AdminController, :list_organizations
    get "/organizations/:id", AdminController, :show_organization
  end

  # Media serving (public/conditional auth — checked inline in controller)
  scope "/media", AnnotateWeb do
    pipe_through [:api]
    get "/:short_id", MediaServeController, :show
    get "/:short_id/*filename", MediaServeController, :show
  end

  # Dashboard attachment downloads: the owner-dashboard inbox links here; the
  # controller 302s to a freshly presigned url, so inbox links never expire.
  # Same cookie session the Hologram dashboard uses; membership (member+) is
  # checked in the controller against the DB on every request.
  pipeline :dashboard_session do
    plug :fetch_session
    plug AnnotateWeb.Plugs.DashboardSession
  end

  scope "/dashboard", AnnotateWeb do
    pipe_through [:dashboard_session]
    get "/attachments/:id", DashboardAttachmentController, :show
  end

  # SAML 2.0 (Samly handles assertion consumer service, metadata, etc.)
  scope "/sso/saml" do
    pipe_through [:saml_login, :sso_session]
    forward "/", Samly.Router
  end

  # OIDC redirect flow
  scope "/auth/oidc", AnnotateWeb do
    pipe_through [:oidc_login, :sso_session]
    get "/", SSOController, :oidc_init
    get "/callback", SSOController, :oidc_callback
  end

  # Social OAuth (ueberauth handles request + callback)
  scope "/auth", AnnotateWeb do
    pipe_through [:oauth_login, :sso_session]
    get "/:provider", SSOController, :oauth_request
    get "/:provider/callback", SSOController, :oauth_callback
  end

  # PBAC v2: Groups & Memberships (authenticated, read-only)
  scope "/api/v1", AnnotateWeb do
    pipe_through [:api, :authenticated]

    get "/groups", GroupController, :index
    get "/groups/:id", GroupController, :show
    get "/groups/:id/policies", GroupController, :policies

    get "/memberships/me", AuthzMembershipController, :my_memberships
    get "/memberships/organizations/:org_id", AuthzMembershipController, :org_members
    get "/memberships/projects/:project_id", AuthzMembershipController, :project_members

    get "/policies/me", PolicyController, :my_policies
    post "/policies/check", PolicyController, :check
    post "/policies/explain", PolicyController, :explain
  end

  # PBAC v2: Projects (authenticated, permission-checked per action)
  scope "/api/v1/organizations/:org_id", AnnotateWeb do
    pipe_through [:api, :authenticated]

    resources "/projects", ProjectController, only: [:index, :create, :show, :update, :delete]

    scope "/projects/:project_id" do
      post "/archive", ProjectController, :archive
      post "/unarchive", ProjectController, :unarchive
      post "/leave", ProjectController, :leave
      get "/members", ProjectController, :members
      post "/members", ProjectController, :add_member
      patch "/members/:member_user_id", ProjectController, :update_member
      delete "/members/:member_user_id", ProjectController, :remove_member
    end
  end

  # PBAC v2: Custom Roles (authenticated, permission-checked per action)
  scope "/api/v1/organizations/:org_id", AnnotateWeb do
    pipe_through [:api, :authenticated]

    resources "/roles", CustomRoleController, only: [:index, :create, :show, :update, :delete]

    scope "/roles/:role_id" do
      get "/permissions", CustomRoleController, :show
      post "/permissions", CustomRoleController, :add_permission
      delete "/permissions/:permission_id", CustomRoleController, :remove_permission
    end
  end

  # PBAC v2: Policy admin (admin only)
  scope "/api/v1", AnnotateWeb do
    pipe_through [:api, :authenticated, :admin]

    resources "/policies", PolicyController, only: [:index, :create, :show, :update, :delete]
    post "/users/:user_id/policies", PolicyController, :attach_to_user
    delete "/users/:user_id/policies/:policy_id", PolicyController, :detach_from_user
  end

  # ── Annotate embeddable comments (/api/v1 + /embed) ──────────────
  # Per-site CORS is handled endpoint-level by AnnotateWeb.Plugs.AnnotateCORS.
  # Token-bound routes carry the site as `?site=<slug>` so preflights (no
  # body) can be authorized — see docs/API.md.

  scope "/api/v1/sites/:site", AnnotateWeb.AnnotateAPI do
    pipe_through [:api, :annotate_rate_limited, :annotate_auth_optional]

    get "/config", SiteConfigController, :show
    get "/me", SiteConfigController, :me
    get "/threads", SiteThreadsController, :index
    post "/threads", SiteThreadsController, :create
  end

  scope "/api/v1", AnnotateWeb.AnnotateAPI do
    pipe_through [:api, :annotate_rate_limited, :annotate_auth_required]

    post "/threads/:id/comments", ThreadCommentsController, :create
    post "/threads/:id/resolve", ThreadCommentsController, :resolve
    post "/threads/:id/reopen", ThreadCommentsController, :reopen
    patch "/threads/:id/anchor", ThreadCommentsController, :patch_anchor
    patch "/comments/:id", CommentController, :update
    delete "/comments/:id", CommentController, :delete
    post "/attachments/presign", AttachmentController, :presign
    post "/attachments/:id/complete", AttachmentController, :complete
  end

  scope "/api/v1", AnnotateWeb.AnnotateAPI do
    pipe_through [:api, :annotate_rate_limited]

    post "/token/refresh", TokenController, :refresh
    post "/token/revoke", TokenController, :revoke
    post "/sites/:site/token/assert", TokenController, :host_assert
  end

  # Popup auth broker (signed session carries state/nonce — same pipeline as
  # the scaffold OIDC flow).
  scope "/embed", AnnotateWeb.AnnotateAPI do
    pipe_through [:sso_session]

    get "/login", EmbedController, :login
    get "/callback", EmbedController, :callback
  end

  # DEV-ONLY devbox login stand-in; compiled out of every non-dev build.
  if Mix.env() == :dev do
    scope "/embed", AnnotateWeb.AnnotateAPI do
      pipe_through [:sso_session]

      get "/dev-login", DevLoginController, :form
      post "/dev-login", DevLoginController, :login
    end
  end

  if Application.compile_env(:annotate, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]
      live_dashboard "/dashboard", metrics: AnnotateWeb.Telemetry
    end
  end
end
