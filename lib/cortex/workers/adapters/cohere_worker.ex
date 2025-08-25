defmodule Cortex.Workers.Adapters.CohereWorker do
  @moduledoc """
  Worker adapter para Cohere API.
  
  Características:
  - Soporte para múltiples API keys con rotación automática
  - Modelos: command, command-light, command-nightly
  - Rate limits: 20 RPM / 1000 monthly calls en free tier
  - Streaming via Server-Sent Events
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
  
  @default_timeout 60_000
  @default_model "command"
  @base_url "https://api.cohere.ai"
  @stream_endpoint "/v1/chat"
  
  @doc """
  Crea una nueva instancia de CohereWorker.
  
  Options:
    - :name - Nombre identificador del worker
    - :api_keys - Lista de API keys para rotación
    - :default_model - Modelo por defecto a usar
    - :timeout - Timeout para peticiones en ms
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
    base_info = APIWorkerBase.worker_info(worker, :cohere)
    
    Map.merge(base_info, %{
      base_url: @base_url,
      default_model: worker.default_model,
      available_models: [
        "command",
        "command-light",
        "command-nightly"
      ]
    })
  end
  
  @impl true
  def priority(_worker), do: 40  # Prioridad media-baja (después de Gemini)
  
  # Callbacks para APIWorkerBase
  
  def provider_config(worker) do
    %{
      base_url: @base_url,
      stream_endpoint: @stream_endpoint,
      health_endpoint: @base_url <> "/v1/models",
      model_param: "model",
      headers_fn: &build_headers/1,
      optional_params: %{
        "temperature" => 0.7,
        "max_tokens" => 2048,
        "stream" => true
      }
    }
  end
  
  def transform_messages(messages, _opts) do
    # Cohere requiere el último mensaje como "message" y el resto como "chat_history"
    case List.pop_at(messages, -1) do
      {nil, []} ->
        raise ArgumentError, "Se requiere al menos un mensaje"
      
      {last_message, history} ->
        %{
          "message" => last_message["content"],
          "chat_history" => transform_chat_history(history)
        }
    end
  end
  
  def extract_content_from_chunk(json_data) do
    case Jason.decode(json_data) do
      {:ok, %{"event_type" => "text-generation", "text" => text}} ->
        text
      
      {:ok, %{"text" => text}} ->
        text
      
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
      {"authorization", "Bearer #{api_key}"},
      {"accept", "text/event-stream"}
    ]
  end
  
  defp transform_chat_history([]), do: []
  defp transform_chat_history(messages) do
    Enum.map(messages, fn message ->
      %{
        "role" => transform_role(message["role"]),
        "message" => message["content"]
      }
    end)
  end
  
  defp transform_role("user"), do: "USER"
  defp transform_role("assistant"), do: "CHATBOT"
  defp transform_role("system"), do: "SYSTEM"
  defp transform_role(role), do: String.upcase(role)
end