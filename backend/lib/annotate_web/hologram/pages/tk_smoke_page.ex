defmodule StarterWeb.Hologram.Pages.TkSmokePage do
  @moduledoc """
  Smoke page for the `:tobor_kit_hologram` mirror package (browser
  verification of the PORTING.md §6.1–6.3 interactive contract — compile /
  render tests cannot cover client-runtime behavior).

  A representative set of mirrors mounts here:

    * stateless: `Sg.Btn`, `PartyCard.Card`, `RobotAvatar.Avatar` (3 states),
      `Faq.Faq`
    * stateful (cid + explicit `target="page"`): `ModeToggle.Toggle`,
      `Persona.Picker`, `ChatThread.Thread`, `PhoneInput.Input`

  Every forwarded action lands in `handle_event/3`, which records it in the
  `last_event` panel so a browser run can observe that a forward actually
  arrived.
  """
  use Hologram.Page

  alias StarterWeb.Hologram.Layouts.MainLayout
  alias ToborKit.Hologram.ChatThread.Thread
  alias ToborKit.Hologram.Faq.Faq
  alias ToborKit.Hologram.ModeToggle.Toggle, as: ModeToggle
  alias ToborKit.Hologram.PartyCard.Card
  alias ToborKit.Hologram.Persona.Picker
  alias ToborKit.Hologram.PhoneInput.Input, as: PhoneInput
  alias ToborKit.Hologram.RobotAvatar.Avatar, as: RobotAvatar
  alias ToborKit.Hologram.Sg.Btn, as: SgBtn

  route "/tk-smoke"
  layout MainLayout, page_title: "tobor-kit smoke"

  def init(_params, component, _server) do
    put_state(component,
      last_event: %{name: "(none yet)", detail: ""},
      event_count: 0,
      faq_items: [
        %{"question" => "What is tobor-kit?", "answer" => "An agent-guide component kit."},
        %{"question" => "Why a smoke page?", "answer" => "Browser-proof the interactive contract."}
      ],
      personas: [
        %{"id" => "sheggoth", "name" => "Sheggoth", "handle" => "@sheggoth"},
        %{"id" => "mask", "name" => "The Mask", "handle" => "@mask"},
        %{"id" => "weego", "name" => "Weego", "handle" => "@weego"}
      ],
      thread_messages: [
        %{id: "m1", role: "assistant", text: "smoke thread ready", at: "", participant: "u2"}
      ],
      thread_participants: [
        %{"id" => "u1", "name" => "Keith"},
        %{"id" => "u2", "name" => "Guide"}
      ],
      msg_seq: 1
    )
  end

  def template do
    ~HOLO"""
    <div class="content" data-cy="smoke.root">
      <h1 class="sg-page-title">tobor-kit hologram smoke</h1>

      <section data-cy="smoke.section.last-event" class="sg-card">
        <h2>Last event</h2>
        <p data-cy="smoke.last-event-name">
          name: <strong>{@last_event.name}</strong>
        </p>
        <p data-cy="smoke.last-event-detail">
          detail: <span>{@last_event.detail}</span>
        </p>
        <p data-cy="smoke.last-event-count">count: <span>{@event_count}</span></p>
      </section>

      <section data-cy="smoke.section.stateless">
        <h2>Stateless mirrors</h2>
        <SgBtn target="page">smoke button</SgBtn>
        <Card display_name="Ada Lovelace" handle="@ada" presence="online" />
        <RobotAvatar cid="smoke-robot-idle" state="idle" />
        <RobotAvatar cid="smoke-robot-thinking" state="thinking" />
        <RobotAvatar cid="smoke-robot-error" state="error" />
        <Faq cid="smoke-faq" items={@faq_items} mode="one" target="page" />
      </section>

      <section data-cy="smoke.section.stateful">
        <h2>Stateful mirrors (target=&quot;page&quot;)</h2>
        <ModeToggle
          cid="smoke-mode-toggle"
          modes={["voice", "text", "transcript"]}
          mode="text"
          target="page"
        />
        <Picker cid="smoke-persona-picker" personas={@personas} target="page" />
        <Thread
          cid="smoke-thread"
          messages={@thread_messages}
          participants={@thread_participants}
          show_composer={true}
          target="page"
        />
        <PhoneInput cid="smoke-phone" name="phone" value="+12125550123" target="page" />
      </section>
    </div>
    """
  end

  # — page-side landing zone for forwarded mirror actions ————————

  def action(:sg_click, _params, component) do
    handle_event(component, "sg-click", "")
  end

  def action(:tobor_mode_change, params, component) do
    handle_event(component, "tobor-mode-change", params.mode <> " (was " <> params.previous <> ")")
  end

  def action(:persona_select, params, component) do
    handle_event(component, "persona-select", params.persona_id)
  end

  def action(:faq_toggle, _params, component) do
    handle_event(component, "faq-toggle", "")
  end

  def action(:phone_change, params, component) do
    handle_event(component, "phone-change", params.value)
  end

  def action(:country_change, params, component) do
    handle_event(component, "country-change", params.country)
  end

  # Composer send → page-owned message append (host owns the transcript).
  def action(:thread_send, params, component) do
    seq = component.state.msg_seq + 1

    put_state(component,
      msg_seq: seq,
      thread_messages: [
        %{
          id: "m" <> Integer.to_string(seq),
          role: "user",
          text: params.text,
          at: "",
          participant: "u1"
        }
        | component.state.thread_messages
      ],
      last_event: %{name: "thread-send", detail: params.text},
      event_count: component.state.event_count + 1
    )
  end

  # Mirrors carry no-op catch-alls; the page mirrors that courtesy.
  def action(_name, _params, component), do: component

  defp handle_event(component, name, detail) do
    put_state(component,
      last_event: %{name: name, detail: detail},
      event_count: component.state.event_count + 1
    )
  end
end
