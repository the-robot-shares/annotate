# Build the sref -> entity handler table once, before any test runs, and fail
# loudly if the Guardian subject handler is missing. A cold build
# `Code.ensure_loaded?`s every app module (seconds in interactive `mix test`);
# warming here keeps that cost out of whichever async test lands first.
Starter.EntityRepo.warm_sref_handlers()
handlers = Starter.EntityRepo.sref_handlers()

Map.has_key?(handlers, "user-session") ||
  raise "sref handler table is missing \"user-session\": #{inspect(Map.keys(handlers))}"

ExUnit.start()

# Shared fixed-id seed rows, committed ONCE before the sandbox goes manual.
# Helpers (ConnCase.setup_user_and_token, sso_test ensure_provider!) and lib
# code reference auth providers by uuid5 id; lazily upserting them per test
# (`on_conflict: :nothing`) makes concurrent sandboxes block on each other's
# uncommitted row (multi-second stalls / pool timeouts). A fresh CI DB always
# hits that path, so seed them up front here instead.
for title <- ~w(Login SmartToken OIDC SAML Google Facebook GitHub LinkedIn) do
  Starter.Repo.insert!(
    %Starter.Schema.Auth.Providers.Provider{
      id: UUID.uuid5(:oid, "Starter.Schema.Auth.Providers.Provider@#{title}"),
      title: title
    },
    on_conflict: :nothing,
    conflict_target: :id
  )
end

Ecto.Adapters.SQL.Sandbox.mode(Starter.Repo, :manual)
