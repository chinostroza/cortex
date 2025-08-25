defmodule Cortex.Workers.Adapters.GeminiWorker do
  @moduledoc """
  Worker adapter para Google Gemini API.
  
  Características:
  - Soporte para múltiples API keys con rotación automática
  - Modelos: gemini-2.0-flash-001, gemini-1.5-pro, gemini-1.5-flash
  - Rate limits: 5 RPM / 25 RPD en free tier
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
  @default_model "gemini-2.0-flash-001"
  @base_url "https://generativelanguage.googleapis.com"
  @stream_endpoint "/v1beta/models/{model}:streamGenerateContent"
  
  @doc """
  Crea una nueva instancia de GeminiWorker.
  
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
    base_info = APIWorkerBase.worker_info(worker, :gemini)
    
    Map.merge(base_info, %{
      base_url: @base_url,
      default_model: worker.default_model,
      available_models: [
        "gemini-2.0-flash-001",
        "gemini-1.5-pro",
        "gemini-1.5-flash"
      ]
    })
  end
  
  @impl true
  def priority(_worker), do: 30  # Prioridad media (después de local, antes de costosos)
  
  # Callbacks para APIWorkerBase
  
  def provider_config(worker) do
    %{
      base_url: @base_url,
      stream_endpoint: String.replace(@stream_endpoint, "{model}", worker.default_model),
      health_endpoint: @base_url <> "/v1beta/models",
      model_param: "model",
      headers_fn: &build_headers/1,
      optional_params: %{
        "generationConfig" => %{
          "candidateCount" => 1,
          "maxOutputTokens" => 2048,
          "temperature" => 0.7
        }
      }
    }
  end
  
  def transform_messages(messages, _opts) do
    # Gemini usa un formato específico con "contents"
    %{
      "contents" => Enum.map(messages, fn message ->
        %{
          "role" => transform_role(message["role"]),
          "parts" => [%{"text" => message["content"]}]
        }
      end)
    }
  end
  
  def extract_content_from_chunk(json_data) do
    case Jason.decode(json_data) do
      {:ok, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => text}]}} | _]}} ->
        text
      
      {:ok, %{"candidates" => [%{"content" => %{"parts" => parts}} | _]}} ->
        # Manejar múltiples partes
        parts
        |> Enum.map(fn part -> Map.get(part, "text", "") end)
        |> Enum.join("")
      
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
      {"x-goog-api-key", api_key},
      {"accept", "text/event-stream"}
    ]
  end
  
  defp transform_role("user"), do: "user"
  defp transform_role("assistant"), do: "model" 
  defp transform_role("system"), do: "user"  # Gemini no tiene role system específico
  defp transform_role(role), do: role
end