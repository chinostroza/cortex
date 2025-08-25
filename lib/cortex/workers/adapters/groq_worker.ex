defmodule Cortex.Workers.Adapters.GroqWorker do
  @moduledoc """
  Worker adapter para Groq API.
  
  Características:
  - Soporte para múltiples API keys con rotación automática
  - Modelos: llama-3.3-70b-versatile, llama-3.1-8b-instant, mixtral-8x7b-32768
  - Rate limits: Variables según tier (ver console.groq.com)
  - Streaming via Server-Sent Events compatible con OpenAI
  - Inferencia súper rápida con LPU (Language Processing Units)
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
  
  @default_timeout 30_000  # Groq es muy rápido, timeout menor
  @default_model "llama-3.1-8b-instant"
  @base_url "https://api.groq.com"
  @stream_endpoint "/openai/v1/chat/completions"
  
  @doc """
  Crea una nueva instancia de GroqWorker.
  
  Options:
    - :name - Nombre identificador del worker
    - :api_keys - Lista de API keys para rotación
    - :default_model - Modelo por defecto a usar
    - :timeout - Timeout para peticiones en ms (default: 30s por velocidad)
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
    base_info = APIWorkerBase.worker_info(worker, :groq)
    
    Map.merge(base_info, %{
      base_url: @base_url,
      default_model: worker.default_model,
      available_models: [
        "llama-3.3-70b-versatile",
        "llama-3.1-8b-instant", 
        "llama-3.1-70b-versatile",
        "mixtral-8x7b-32768",
        "gemma2-9b-it"
      ],
      special_features: [
        "ultra_fast_inference",
        "lpu_acceleration", 
        "openai_compatible"
      ]
    })
  end
  
  @impl true
  def priority(_worker), do: 20  # Prioridad alta (después de local, pero antes de otros cloud)
  
  # Callbacks para APIWorkerBase
  
  def provider_config(worker) do
    %{
      base_url: @base_url,
      stream_endpoint: @stream_endpoint,
      health_endpoint: @base_url <> "/openai/v1/models",
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
    # Groq usa formato compatible con OpenAI, no necesita transformación
    messages
  end
  
  def extract_content_from_chunk(json_data) do
    case Jason.decode(json_data) do
      {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}} when is_binary(content) ->
        content
      
      {:ok, %{"choices" => [%{"delta" => %{"content" => nil}} | _]}} ->
        ""
      
      {:ok, %{"choices" => [%{"finish_reason" => _reason} | _]}} ->
        # Stream terminado
        ""
      
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
end