# lib/cortex_web/controllers/v1/chat_controller.ex

defmodule CortexWeb.V1.ChatController do
  use CortexWeb, :controller
  
  @doc """
  Endpoint compatible con OpenAI: POST /v1/chat/completions
  
  Recibe:
  {
    "model": "gpt-5",
    "messages": [...],
    "stream": true,
    "temperature": 0.7
  }
  
  Devuelve formato OpenAI estándar.
  """
  def completions(conn, params) do
    model = Map.get(params, "model")
    messages = Map.get(params, "messages")
    
    unless model && messages do
      send_resp(conn, 400, Jason.encode!(%{
        "error" => %{
          "type" => "invalid_request_error",
          "message" => "Missing required fields: model, messages"
        }
      }))
    else
      # Mapear modelo a worker interno
      case map_model_to_worker(model) do
        {:ok, worker_opts} ->
          dispatch_to_worker(conn, messages, worker_opts, params)
        
        {:error, :unsupported_model} ->
          send_resp(conn, 400, Jason.encode!(%{
            "error" => %{
              "type" => "invalid_request_error", 
              "message" => "Unsupported model: #{model}"
            }
          }))
      end
    end
  end
  
  # Mapear modelo OpenAI → configuración worker interno
  defp map_model_to_worker(model) do
    case model do
      # OpenAI GPT models
      "gpt-5" -> {:ok, %{provider: "openai", model: "gpt-5"}}
      "gpt-5-mini" -> {:ok, %{provider: "openai", model: "gpt-5-mini"}}
      "gpt-5-nano" -> {:ok, %{provider: "openai", model: "gpt-5-nano"}}
      "gpt-4" -> {:ok, %{provider: "openai", model: "gpt-4"}}
      "gpt-4-turbo" -> {:ok, %{provider: "openai", model: "gpt-4-turbo"}}
      "gpt-3.5-turbo" -> {:ok, %{provider: "openai", model: "gpt-3.5-turbo"}}
      
      # Fallback temporal para gpt-4 (usar Groq si OpenAI no disponible)
      "gpt-4-fallback" -> {:ok, %{provider: "groq", model: "llama-3.1-8b-instant"}}
      
      # Google Gemini
      "gemini-2.5-pro" -> {:ok, %{provider: "gemini_pro_25", model: "gemini-2.5-pro"}}
      "gemini-2.5-flash" -> {:ok, %{provider: "gemini_pro_25", model: "gemini-2.5-flash"}}
      "gemini-pro-2.5" -> {:ok, %{provider: "gemini_pro_25", model: "gemini-2.5-pro"}}  # Alias
      "gemini-2.0-flash" -> {:ok, %{provider: "gemini", model: "gemini-2.0-flash-001"}}
      
      # X.AI Grok models
      "grok-code-fast-1" -> {:ok, %{provider: "xai", model: "grok-code-fast-1"}}
      "grok-beta" -> {:ok, %{provider: "xai", model: "grok-beta"}}
      "grok-4" -> {:ok, %{provider: "xai", model: "grok-4"}}
      
      # Anthropic Claude
      "claude-sonnet-4" -> {:ok, %{provider: "anthropic", model: "claude-sonnet-4-20250514"}}
      "claude-sonnet-4-20250514" -> {:ok, %{provider: "anthropic", model: "claude-sonnet-4-20250514"}}
      "claude-3.7-sonnet" -> {:ok, %{provider: "anthropic", model: "claude-3.7-sonnet"}}
      "claude-3.5-haiku" -> {:ok, %{provider: "anthropic", model: "claude-3.5-haiku"}}
      
      _ -> {:error, :unsupported_model}
    end
  end
  
  defp dispatch_to_worker(conn, messages, worker_opts, params) do
    # Convertir parámetros OpenAI a formato interno
    internal_opts = [
      provider: worker_opts.provider,
      model: Map.get(worker_opts, :model),
      temperature: Map.get(params, "temperature"),
      stream: Map.get(params, "stream", true)
    ]
    
    # Usar dispatcher existente
    case Cortex.Dispatcher.dispatch_stream(messages, internal_opts) do
      {:ok, stream} ->
        send_openai_format_stream(conn, stream, params)
      
      {:error, reason} ->
        send_resp(conn, 500, Jason.encode!(%{
          "error" => %{
            "type" => "internal_error",
            "message" => "Failed to process request: #{inspect(reason)}"
          }
        }))
    end
  end
  
  defp send_openai_format_stream(conn, stream, params) do
    if Map.get(params, "stream", true) do
      # Streaming response formato OpenAI
      conn = send_chunked(conn, 200)
      
      stream
      |> Enum.reduce_while(conn, fn chunk, acc_conn ->
        openai_chunk = format_as_openai_chunk(chunk)
        
        case Plug.Conn.chunk(acc_conn, "data: #{Jason.encode!(openai_chunk)}\n\n") do
          {:ok, new_conn} -> {:cont, new_conn}
          {:error, _} -> {:halt, acc_conn}
        end
      end)
      
      # Final chunk
      Plug.Conn.chunk(conn, "data: [DONE]\n\n")
    else
      # Non-streaming (por implementar)
      send_resp(conn, 501, "Non-streaming not implemented yet")
    end
  end
  
  defp format_as_openai_chunk(content) do
    %{
      "id" => "chatcmpl-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}",
      "object" => "chat.completion.chunk",
      "created" => System.system_time(:second),
      "model" => "cortex-gateway",
      "choices" => [
        %{
          "index" => 0,
          "delta" => %{"content" => content},
          "finish_reason" => nil
        }
      ]
    }
  end
end