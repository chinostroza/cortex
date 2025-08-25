defmodule Cortex.Workers.Adapters.OllamaWorker do
  @moduledoc """
  Worker adapter para servidores Ollama.
  
  Este módulo se encarga exclusivamente de la comunicación con una instancia
  específica de Ollama, implementando el behaviour Worker.
  """
  
  @behaviour Cortex.Workers.Worker
  
  defstruct [:name, :base_url, :models, :timeout]
  
  @default_timeout 60_000
  
  @doc """
  Crea una nueva instancia de OllamaWorker.
  
  Options:
    - :name - Nombre identificador del worker
    - :base_url - URL base del servidor Ollama (ej: "http://localhost:11434")
    - :models - Lista de modelos disponibles (se detectan automáticamente si no se especifica)
    - :timeout - Timeout para las peticiones en ms (default: 60000)
  """
  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      base_url: Keyword.fetch!(opts, :base_url),
      models: Keyword.get(opts, :models, []),
      timeout: Keyword.get(opts, :timeout, @default_timeout)
    }
  end
  
  @impl true
  def health_check(%__MODULE__{base_url: base_url, timeout: timeout}) do
    case Req.get(base_url <> "/api/tags", receive_timeout: timeout) do
      {:ok, %{status: 200}} ->
        {:ok, :available}
      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @impl true
  def stream_completion(%__MODULE__{} = worker, messages, opts) do
    model = Keyword.get(opts, :model, "gemma3:4b")
    
    payload = %{
      model: model,
      messages: messages,
      stream: true
    }
    
    request = build_request(worker, payload)
    
    stream = create_stream(request, worker.timeout)
    {:ok, stream}
  rescue
    error -> {:error, error}
  end
  
  @impl true
  def info(%__MODULE__{} = worker) do
    %{
      name: worker.name,
      type: :ollama,
      base_url: worker.base_url,
      models: worker.models,
      timeout: worker.timeout
    }
  end
  
  @impl true
  def priority(%__MODULE__{}), do: 10  # Alta prioridad para workers locales
  
  # Funciones privadas
  
  defp build_request(worker, payload) do
    Finch.build(
      :post,
      worker.base_url <> "/api/chat",
      [{"content-type", "application/json"}],
      Jason.encode!(payload)
    )
  end
  
  defp create_stream(request, timeout) do
    Stream.unfold(:init, fn
      :init ->
        parent = self()
        ref = make_ref()
        
        spawn(fn ->
          Finch.stream(request, Req.Finch, "", fn
            {:status, _status}, acc -> acc
            {:headers, _headers}, acc -> acc
            {:data, data}, acc ->
              data
              |> String.split("\n", trim: true)
              |> Enum.each(fn line ->
                send(parent, {ref, {:chunk, line}})
              end)
              acc
          end)
          send(parent, {ref, :done})
        end)
        
        {nil, {ref, :streaming}}
        
      {ref, :streaming} = state ->
        receive do
          {^ref, :done} -> nil
          {^ref, {:chunk, chunk}} -> {chunk, state}
        after
          timeout -> nil
        end
        
      _ ->
        nil
    end)
    |> Stream.reject(&is_nil/1)
  end
end