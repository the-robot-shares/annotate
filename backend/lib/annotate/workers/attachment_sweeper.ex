defmodule Annotate.Workers.AttachmentSweeper do
  @moduledoc """
  Hourly Oban cron job: deletes `pending` attachments older than 24h
  (uploads that never completed `POST /attachments/:id/complete`).
  """
  use Oban.Worker, queue: :cleanup, max_attempts: 1

  @impl Oban.Worker
  def perform(_job) do
    {:ok, _count} = Annotate.Comments.sweep_stale_pending()
    :ok
  end
end
