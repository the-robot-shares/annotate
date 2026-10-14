defmodule Starter.Workers.EmailWorker do
  use Oban.Worker, queue: :mailer, max_attempts: 3

  @impl Oban.Worker
  # <REMOVED UUID HERE> perform :: auto-generated pointer for public function perform
  def perform(%Oban.Job{args: %{"type" => "magic_link", "to" => to, "link" => link}}) do
    Starter.Auth.SmartTokenEmail.send_magic_link(to, link)
    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "otp_login", "to" => to, "code" => code}}) do
    Starter.Auth.SmartTokenEmail.send_otp_login(to, code)
    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "password_reset", "to" => to, "code" => code}}) do
    Starter.Auth.SmartTokenEmail.send_password_reset(to, code)
    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "verification", "to" => to, "link" => link}}) do
    Starter.Auth.SmartTokenEmail.send_verification_email(to, link)
    :ok
  end

  # <REMOVED UUID HERE> enqueue :: auto-generated pointer for public function enqueue
  def enqueue(type, to, extra) do
    args = Map.merge(%{"type" => type, "to" => to}, extra)

    args
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
