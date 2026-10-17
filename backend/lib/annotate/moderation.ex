defmodule Annotate.Moderation do
  @moduledoc """
  AI content moderation for comment text and comment attachments via Alibaba
  DashScope's OpenAI-compatible `/chat/completions` endpoint.

  - comment bodies (create AND edit) and `text/plain` attachments →
    `:text_model` (default `qwen3.8-flash`);
  - image attachments → the vision `:image_model` (default `qwen-vl-flash`),
    the bytes as a base64 data URL on the same API key.

  **Fail-open by design** (user decision, session ledger Q1): an unset
  `ANNOTATE_DASHSCOPE_API_KEY`, network error, timeout (≤ 3s budget),
  non-200 response or unparseable answer all ALLOW the content and log a
  single warning line — never the content itself, never the key. Only an
  affirmative `profanity` / `inappropriate` classification blocks the write.

  Config (`config/runtime.exs`, all env-overridable): `:api_key`,
  `:base_url` (default DashScope compatible-mode, international region),
  `:text_model`, `:image_model`, `:timeout_ms`. Soft-disabled until the key
  exists in Infisical /apps/annotate — no call is made when it is unset.

  Only writes pay the latency: the filter runs on comment create/edit and on
  attachment completion, never on reads.
  """

  require Logger

  @timeout_ms 3_000
  # Long text attachments are truncated for classification; the model only
  # needs a sample to classify, and huge payloads would blow the 3s budget.
  @max_text_bytes 100_000

  def cfg, do: Application.get_env(:annotate, __MODULE__, [])

  def enabled?, do: is_binary(cfg()[:api_key]) and cfg()[:api_key] != ""

  @doc """
  Comment-text gate. `:ok` | `{:error, :content_rejected}`. Fail-open on
  every error/unavailable path.
  """
  def check_text(body) when is_binary(body) and byte_size(body) > 0 do
    if enabled?() do
      classify_text(body)
    else
      :ok
    end
  end

  def check_text(_), do: :ok

  @doc "Polite user-facing 422 payload for rejected content (comments)."
  def rejection_payload do
    %{
      "error" => "content_rejected",
      "message" =>
        "Your comment looks like it may contain language that isn't allowed here. " <>
          "Please revise it and try again."
    }
  end

  @doc """
  Attachment gate by content type. `:ok` | `{:error, :content_rejected}` |
  `:skip` (type we do not classify — PDFs etc.). `binary` is the stored
  object; pass it for images and text, anything for skippable types.
  Soft-disabled (no key) ⇒ `:ok` without any call.
  """
  def check_attachment(content_type, binary) do
    if enabled?() do
      case content_type do
        "image/" <> _ when is_binary(binary) -> classify_image(binary)
        "text/plain" when is_binary(binary) -> classify_text(binary)
        _ -> :skip
      end
    else
      :ok
    end
  end

  # ── Classification ────────────────────────────────────────────

  defp classify_text(text) do
    prompt = """
    You are a strict content moderation classifier for a public commenting
    system. Decide whether the user message contains profanity, slurs, sexual
    explicitness, or abusive harassment aimed at people. Mild frustration
    without profanity is clean. Reply with ONLY a JSON object and nothing
    else: {"classification":"clean"} or {"classification":"profanity"}.
    """

    content = text |> slice()

    case chat(text_model(), [%{role: "system", content: prompt}, %{role: "user", content: content}]) do
      {:ok, answer} ->
        if classify(answer) == "profanity" do
          {:error, :content_rejected}
        else
          :ok
        end

      :fail_open ->
        :ok
    end
  end

  defp classify_image(binary) do
    prompt = """
    You are a strict image moderation classifier for a public commenting
    system. Decide whether the image is inappropriate: nudity or sexual
    content, graphic violence or gore, hate symbols, or illegal content.
    Ordinary screenshots, diagrams and photos are clean. Reply with ONLY a
    JSON object and nothing else: {"classification":"clean"} or
    {"classification":"inappropriate"}.
    """

    content = [
      %{type: "text", text: prompt},
      %{type: "image_url", image_url: %{url: "data:image;base64," <> Base.encode64(binary)}}
    ]

    case chat(image_model(), [%{role: "user", content: content}]) do
      {:ok, answer} ->
        if classify(answer) == "inappropriate", do: {:error, :content_rejected}, else: :ok

      :fail_open ->
        :ok
    end
  end

  # One OpenAI-compatible chat completion. Any failure → `:fail_open` with a
  # single warning line (status/reason only — never content, never the key).
  defp chat(model, messages) do
    key = cfg()[:api_key]

    if not is_binary(key) or key == "",
      do: :fail_open,
      else: do_chat(model, messages, key)
  end

  defp do_chat(model, messages, key) do
    base = String.trim_trailing(cfg()[:base_url] || default_base_url(), "/")
    url = base <> "/chat/completions"
    timeout = cfg()[:timeout_ms] || @timeout_ms

    payload = %{model: model, messages: messages, temperature: 0}

    case Req.post(url,
           json: payload,
           headers: [{"authorization", "Bearer " <> key}],
           receive_timeout: timeout,
           retry: false
         ) do
      {:ok, %Req.Response{status: 200} = resp} ->
        case resp.body do
          %{"choices" => [%{"message" => %{"content" => content}} | _]} when is_binary(content) ->
            {:ok, content}

          _ ->
            Logger.warning("[moderation] dashscope malformed response model=#{model} — allowing")
            :fail_open
        end

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("[moderation] dashscope non-200 status=#{status} model=#{model} — allowing")
        :fail_open

      {:error, exception} ->
        Logger.warning(
          "[moderation] dashscope unreachable model=#{model} reason=#{inspect(exception.__struct__)} — allowing"
        )

        :fail_open
    end
  rescue
    e ->
      Logger.warning("[moderation] dashscope call crashed reason=#{inspect(e.__struct__)} — allowing")
      :fail_open
  end

  # The answer may carry markdown fences or stray prose; take the first JSON
  # object and read `classification`. Anything unreadable = fail-open.
  defp classify(answer) do
    case Regex.run(~r/\{[^{}]*\}/, answer) do
      [json | _] ->
        case Jason.decode(json) do
          {:ok, %{"classification" => value}} when is_binary(value) ->
            String.downcase(String.trim(value))

          _ ->
            "unknown"
        end

      nil ->
        "unknown"
    end
  end

  defp text_model, do: cfg()[:text_model] || "qwen3.8-flash"
  defp image_model, do: cfg()[:image_model] || "qwen-vl-flash"
  defp default_base_url, do: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"

  defp slice(text) when byte_size(text) > @max_text_bytes do
    String.slice(text, 0, @max_text_bytes)
  end

  defp slice(text), do: text
end
