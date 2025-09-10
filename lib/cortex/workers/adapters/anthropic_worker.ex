defmodule Cortex.Workers.Adapters.AnthropicWorker do
  @moduledoc """
  Worker adapter para Anthropic Claude models.
  
  Características:
  - Modelos: claude-sonnet-4-20250514, claude-3.7-sonnet, claude-3.5-haiku
  - Context: 1M tokens (beta para Claude 4)
  - Extended thinking, tool use, parallel tools
  - Especializado en reasoning avanzado y coding
  """
  
  @behaviour Cortex.Workers.Worker
  
  alias Cortex.Workers.Adapters.APIWorkerBase
  
  defstruct [
    :name,
    :api_keys,
    :current_key_index,
    :default_model,
    :timeout,
    :last_rotation
  ]
  
  @default_timeout 60_000  # Claude 4 tiene timeout de 60 minutos
  @default_model "claude-sonnet-4-20250514"
  @base_url "https://api.anthropic.com"
  @stream_endpoint "/v1/messages"
  
  @doc """
  Crea una nueva instancia de AnthropicWorker.
  """
  def new(opts) do
    api_keys = case Keyword.get(opts, :api_keys) do
      keys when is_list(keys) and keys != [] -> keys
      single_key when is_binary(single_key) -> [single_key]
      _ -> raise ArgumentError, "api_keys debe ser una lista no vacía o string"
    end
    
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      api_keys: api_keys,
      current_key_index: 0,
      default_model: Keyword.get(opts, :default_model, @default_model),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      last_rotation: nil
    }
  end
  
  @impl true
  def health_check(worker) do
    APIWorkerBase.health_check(worker)
  end
  
  @impl true
  def stream_completion(worker, messages, opts) do
    APIWorkerBase.stream_completion(worker, messages, opts)
  end
  
  @impl true
  def info(worker) do
    base_info = APIWorkerBase.worker_info(worker, :anthropic)
    
    Map.merge(base_info, %{
      base_url: @base_url,
      default_model: worker.default_model,
      available_models: [
        "claude-sonnet-4-20250514",
        "claude-3.7-sonnet",
        "claude-3.5-haiku"
      ]
    })
  end
  
  @impl true
  def priority(_worker), do: 10  # Alta prioridad (después de OpenAI)
  
  # Callbacks para APIWorkerBase
  
  def provider_config(_worker) do
    %{
      base_url: @base_url,
      stream_endpoint: @stream_endpoint,
      health_endpoint: @base_url <> "/v1/messages",
      model_param: "model",
      headers_fn: &build_headers/1,
      optional_params: %{
        "max_tokens" => 4096,
        "stream" => true,
        "temperature" => 0.7
      }
    }
  end
  
  def transform_messages(messages, _opts) do
    # Separar system message del resto
    {system_messages, user_messages} = Enum.split_with(messages, fn msg ->
      msg["role"] == "system"
    end)
    
    # Claude usa system parameter separado
    base_request = %{
      "messages" => Enum.map(user_messages, fn message ->
        %{
          "role" => transform_role(message["role"]),
          "content" => message["content"]
        }
      end)
    }
    
    # Agregar system prompt si existe
    case system_messages do
      [system_msg | _] ->
        Map.put(base_request, "system", system_msg["content"])
      [] ->
        base_request
    end
  end
  
  def extract_content_from_chunk(json_data) do
    case Jason.decode(json_data) do
      # Formato de streaming de Claude
      {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
        text
      
      # Formato de respuesta completa
      {:ok, %{"content" => [%{"text" => text} | _]}} ->
        text
      
      {:ok, %{"content" => [%{"type" => "text", "text" => text} | _]}} ->
        text
      
      # Ignorar eventos de control
      {:ok, %{"type" => "message_start"}} -> ""
      {:ok, %{"type" => "content_block_start"}} -> ""
      {:ok, %{"type" => "content_block_stop"}} -> ""
      {:ok, %{"type" => "message_stop"}} -> ""
      
      _ ->
        ""
    end
  end
  
  @doc """
  Rota al siguiente API key disponible.
  """
  def rotate_api_key(worker) do
    new_index = rem(worker.current_key_index + 1, length(worker.api_keys))
    
    %{worker | 
      current_key_index: new_index,
      last_rotation: DateTime.utc_now()
    }
  end
  
  @doc """
  Obtiene el API key actual.
  """
  def current_api_key(worker) do
    Enum.at(worker.api_keys, worker.current_key_index)
  end
  
  # Funciones privadas
  
  defp build_headers(worker) do
    api_key = current_api_key(worker)
    [
      {"x-api-key", api_key},
      {"Content-Type", "application/json"},
      {"anthropic-version", "2023-06-01"},
      # Beta header para extended thinking
      {"anthropic-beta", "interleaved-thinking-2025-05-14"}
    ]
  end
  
  defp transform_role("user"), do: "user"
  defp transform_role("assistant"), do: "assistant"
  defp transform_role("system"), do: "user"  # System se maneja por separado
  defp transform_role(role), do: role
end