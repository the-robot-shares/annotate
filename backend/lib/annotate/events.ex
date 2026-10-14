defmodule Annotate.Events do
  require Logger

  @type_list [
    :user_registered,
    :user_verified,
    :org_created,
    :org_member_added,
    :org_member_removed,
    :org_member_role_changed
  ]

  # <REMOVED UUID HERE> dispatch :: auto-generated pointer for public function dispatch
  def dispatch(event_type, payload) when event_type in @type_list do
    Logger.info("Event dispatched: #{event_type}")
    Phoenix.PubSub.broadcast(Annotate.PubSub, "events", {event_type, payload})
  end

  def dispatch(event_type, _payload) do
    Logger.warning("Unknown event type: #{event_type}")
    :ok
  end

  # <REMOVED UUID HERE> subscribe :: auto-generated pointer for public function subscribe
  def subscribe do
    Phoenix.PubSub.subscribe(Annotate.PubSub, "events")
  end
end
