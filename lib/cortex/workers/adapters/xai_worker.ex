defmodule Cortex.Workers.Adapters.XAIWorker do
  @moduledoc """
  Worker adapter para X.AI Grok models.
  
  Características:
  - Modelos: grok-code-fast-1, grok-beta, grok-4
  - API compatible con OpenAI
  - Especializado en coding y reasoning
  - Context: 128K tokens (grok-beta)
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
  
  @default_timeout 30_000
  @default_model "grok-code-fast-1"
  @base_url "https://api.x.ai"
  @stream_endpoint "/v1/chat/completions"
  
  @doc """
  Crea una nueva instancia de XAIWorker.
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
    base_info = APIWorkerBase.worker_info(worker, :xai)
    
    Map.merge(base_info, %{
      base_url: @base_url,
      default_model: worker.default_model,
      available_models: [
        "grok-code-fast-1",
        "grok-beta", 
        "grok-4"
      ]
    })
  end
  
  @impl true
  def priority(_worker), do: 15  # Alta prioridad para coding (después de local)
  
  # Callbacks para APIWorkerBase
  
  def provider_config(_worker) do
    %{
      base_url: @base_url,
      stream_endpoint: @stream_endpoint,
      health_endpoint: @base_url <> "/v1/models",
      model_param: "model",
      headers_fn: &build_headers/1,
      optional_params: %{
        "stream" => true,
        "temperature" => 0.3  # Más determinista para código
      }
    }
  end
  
  def transform_messages(messages, _opts) do
    # X.AI usa formato OpenAI estándar
    %{
      "messages" => messages
    }
  end
  
  def extract_content_from_chunk(json_data) do
    case Jason.decode(json_data) do
      {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}} ->
        content
      
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        content
      
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
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]
  end
end