defmodule Noizu.LiveViewEventServer do
  use GenServer
  require Noizu.LiveViewEvent
  import Noizu.LiveViewEvent

  # <REMOVED UUID HERE> start_link :: auto-generated pointer for public function start_link
  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: {:global, __MODULE__})
  end

  @impl true
  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(:ok) do
    :syn.add_node_to_scopes([:live_view_dispatch])
    {:ok, %{}}
  end

  # <REMOVED UUID HERE> subscribe :: auto-generated pointer for public function subscribe
  def subscribe(group)

  def subscribe(group) do
    :syn.join(:live_view_dispatch, group, self())
  end

  # <REMOVED UUID HERE> unsubscribe :: auto-generated pointer for public function unsubscribe
  def unsubscribe(group)

  def unsubscribe(group) do
    :syn.leave(:live_view_dispatch, group, self())
  end

  # <REMOVED UUID HERE> publish :: auto-generated pointer for public function publish
  def publish(event)

  def publish(event_msg(subject: subject, instance: :*) = msg) do
    :syn.publish(:live_view_dispatch, {subject, :*}, msg)
  end

  def publish(event_msg(subject: subject, instance: instance) = msg) do
    :syn.publish(:live_view_dispatch, {subject, :*}, msg)
    :syn.publish(:live_view_dispatch, {subject, instance}, msg)
  end

  def publish(session, event)

  def publish(session, event_msg(subject: subject, instance: :*) = msg) do
    :syn.publish(:live_view_dispatch, {session, {subject, :*}}, msg)
    :syn.publish(:live_view_dispatch, {subject, :*}, msg)
  end

  def publish(session, event_msg(subject: subject, instance: instance) = msg) do
    :syn.publish(:live_view_dispatch, {session, {subject, :*}}, msg)
    :syn.publish(:live_view_dispatch, {session, {subject, instance}}, msg)
    :syn.publish(:live_view_dispatch, {subject, :*}, msg)
    :syn.publish(:live_view_dispatch, {subject, instance}, msg)
  end
end
