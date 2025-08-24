# en lib/cortex/dispatcher.ex

defmodule Cortex.Dispatcher do
  @ollama_url "http://localhost:11434"

  def dispatch(messages) do
    payload = %{
      model: "gemma3:4b",
      messages: messages,
      stream: true # Dejamos esto en true para que Ollama nos envíe el formato correcto
    }

    opts = [
      json: payload,
      receive_timeout: 60_000
    ]

    case Req.post(@ollama_url <> "/api/chat", opts) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
