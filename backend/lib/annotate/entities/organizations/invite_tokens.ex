defmodule Annotate.Organizations.InviteTokens do
  @moduledoc """
  Repo for Annotate.Organizations.InviteToken
  """
  alias Annotate.Organizations.InviteToken, as: Entity
  use Noizu.Repo
  def_repo(entity: Entity)
end
