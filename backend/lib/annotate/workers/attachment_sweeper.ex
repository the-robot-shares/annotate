defmodule Annotate.Workers.AttachmentSweeper do
  @moduledoc """
  Hourly Oban cron job: deletes `pending` attachments older than 24h
  (uploads that never completed `POST /attachments/:id/complete`) and
  re-enforces the rolling comment-attachment storage cap
  (`Annotate.Storage.Rotation` — also run inline after every completed
  upload; this pass is the self-heal for abandoned uploads and drift).
  """
  use Oban.Worker, queue: :cleanup, max_attempts: 1

  @impl Oban.Worker
  def perform(_job) do
    {:ok, _count} = Annotate.Comments.sweep_stale_pending()
    {:ok, _evicted} = Annotate.Storage.Rotation.enforce()
    :ok
  end
end
