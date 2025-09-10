defmodule Cortex.Workers.Adapters.GeminiPro25Worker do
  @moduledoc """
  Worker adapter para Google Gemini Pro 2.5.
  
  Características:
  - Modelo: gemini-2.5-pro (advanced reasoning)
  - Context: 128K tokens
  - Multimodal: text, audio, images, video, code repositories
  - Especializado en reasoning complejo y análisis de datasets
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
  @default_model "gemini-2.5-pro"
  @base_url "https://generativelanguage.googleapis.com"
  @stream_endpoint "/v1beta/models/gemini-2.5-pro:streamGenerateContent"
  
  @doc """
  Crea una nueva instancia de GeminiPro25Worker.
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
    base_info = APIWorkerBase.worker_info(worker, :gemini_pro_25)
    
    Map.merge(base_info, %{
      base_url: @base_url,
      default_model: worker.default_model,
      available_models: [
        "gemini-2.5-pro",
        "gemini-2.5-flash"
      ]
    })
  end
  
  @impl true
  def priority(_worker), do: 25  # Prioridad media-alta (después de GPT-5 y Grok)
  
  # Callbacks para APIWorkerBase
  
  def provider_config(_worker) do
    %{
      base_url: @base_url,
      stream_endpoint: @stream_endpoint,
      health_endpoint: @base_url <> "/v1beta/models",
      model_param: "model",
      headers_fn: &build_headers/1,
      optional_params: %{
        "generationConfig" => %{
          "candidateCount" => 1,
          "maxOutputTokens" => 8192,
          "temperature" => 0.9,
          "topK" => 64,
          "topP" => 0.95
        },
        "safetySettings" => [
          %{
            "category" => "HARM_CATEGORY_HARASSMENT",
            "threshold" => "BLOCK_MEDIUM_AND_ABOVE"
          },
          %{
            "category" => "HARM_CATEGORY_HATE_SPEECH", 
            "threshold" => "BLOCK_MEDIUM_AND_ABOVE"
          },
          %{
            "category" => "HARM_CATEGORY_SEXUALLY_EXPLICIT",
            "threshold" => "BLOCK_MEDIUM_AND_ABOVE"
          },
          %{
            "category" => "HARM_CATEGORY_DANGEROUS_CONTENT",
            "threshold" => "BLOCK_MEDIUM_AND_ABOVE"
          }
        ]
      }
    }
  end
  
  def transform_messages(messages, _opts) do
    # Gemini usa formato específico con "contents"
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
      {"X-goog-api-key", api_key},
      {"Content-Type", "application/json"}
    ]
  end
  
  defp transform_role("user"), do: "user"
  defp transform_role("assistant"), do: "model" 
  defp transform_role("system"), do: "user"  # Gemini no tiene role system específico
  defp transform_role(role), do: role
end