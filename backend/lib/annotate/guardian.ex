defmodule Annotate.Guardian do
  use Guardian, otp_app: :annotate

  # <REMOVED UUID HERE> subject_for_token :: auto-generated pointer for public function subject_for_token
  def subject_for_token(%Annotate.Users.Sessions.UserSession{} = session, _claims) do
    Noizu.EntityReference.Protocol.sref(session)
  end

  def subject_for_token(_, _) do
    {:error, :unhandled_resource}
  end

  # <REMOVED UUID HERE> resource_from_claims :: auto-generated pointer for public function resource_from_claims
  def resource_from_claims(%{"sub" => "ref.user-session." <> _ = sref}) do
    Noizu.EntityReference.Protocol.entity(sref, Noizu.Context.system())
  end

  def resource_from_claims(_claims) do
    {:error, :invalid_claims}
  end
end
