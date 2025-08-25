defmodule Cortex.Workers.Adapters.APIWorkerBase do
  @moduledoc """
  Módulo base para workers de APIs externas.
  
  Proporciona funcionalidades comunes para reducir duplicación de código:
  - Manejo de API keys
  - Construcción de headers HTTP
  - Manejo de timeouts y errores comunes
  - Streaming con Server-Sent Events (SSE)
  """
  
  @doc """
  Callback para obtener la configuración específica del provider.
  
  Debe retornar:
  - base_url: URL base de la API
  - stream_endpoint: endpoint específico para streaming
  - model_param: nombre del parámetro para el modelo
  - headers_fn: función para construir headers específicos
  """
  @callback provider_config(worker :: struct()) :: map()
  
  @doc """
  Callback para transformar mensajes al formato específico del provider.
  """
  @callback transform_messages(messages :: list(), opts :: keyword()) :: term()
  
  @doc """
  Callback para extraer contenido del chunk de streaming específico del provider.
  """
  @callback extract_content_from_chunk(chunk :: String.t()) :: String.t()
  
  @doc """
  Realiza health check genérico para APIs REST.
  """
  def health_check(worker) do
    config = apply(worker.__struct__, :provider_config, [worker])
    
    # Usar endpoint de health check si existe, sino usar el base_url
    health_url = Map.get(config, :health_endpoint, config.base_url)
    
    # Incluir headers de autenticación para el health check
    headers = config.headers_fn.(worker)
    
    case Req.get(health_url, headers: headers, receive_timeout: worker.timeout) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, :available}
      {:ok, %{status: status}} when status in 400..499 ->
        {:error, {:client_error, status}}
      {:ok, %{status: status}} when status in 500..599 ->
        {:error, {:server_error, status}}
      {:error, %{reason: :timeout}} ->
        {:error, :timeout}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Realiza streaming genérico para APIs que usan Server-Sent Events.
  """
  def stream_completion(worker, messages, opts) do
    config = apply(worker.__struct__, :provider_config, [worker])
    
    # Transformar mensajes al formato del provider
    transformed_messages = apply(worker.__struct__, :transform_messages, [messages, opts])
    
    # Construir payload
    payload = build_payload(worker, transformed_messages, config, opts)
    
    # Construir request
    url = config.base_url <> config.stream_endpoint
    headers = apply(config.headers_fn, [worker])
    
    request = Finch.build(
      :post,
      url,
      [{"content-type", "application/json"} | headers],
      Jason.encode!(payload)
    )
    
    # Crear stream
    stream = create_sse_stream(request, worker)
    {:ok, stream}
  rescue
    error -> {:error, error}
  end
  
  @doc """
  Información genérica del worker.
  """
  def worker_info(worker, type) do
    %{
      name: worker.name,
      type: type,
      api_keys_count: length(worker.api_keys),
      current_key_index: worker.current_key_index,
      timeout: worker.timeout,
      last_rotation: worker.last_rotation
    }
  end
  
  # Funciones privadas
  
  defp build_payload(worker, messages, config, opts) do
    model = Keyword.get(opts, :model, worker.default_model)
    
    base_payload = %{
      config.model_param => model,
      "messages" => messages,
      "stream" => true
    }
    
    # Agregar parámetros opcionales si existen
    optional_params = Map.get(config, :optional_params, %{})
    Map.merge(base_payload, optional_params)
  end
  
  defp create_sse_stream(request, worker) do
    Stream.unfold(:init, fn
      :init ->
        parent = self()
        ref = make_ref()
        
        spawn(fn ->
          Finch.stream(request, Req.Finch, "", fn
            {:status, _status}, acc -> acc
            {:headers, _headers}, acc -> acc
            {:data, data}, acc ->
              # Procesar Server-Sent Events
              process_sse_data(data, parent, ref, worker)
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
          worker.timeout -> nil
        end
        
      _ ->
        nil
    end)
    |> Stream.reject(&is_nil/1)
  end
  
  defp process_sse_data(data, parent, ref, worker) do
    # Dividir por líneas para manejar múltiples eventos SSE
    data
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      cond do
        String.starts_with?(line, "data: ") ->
          json_data = String.replace_prefix(line, "data: ", "")
          
          unless json_data == "[DONE]" do
            content = apply(worker.__struct__, :extract_content_from_chunk, [json_data])
            if content != "" do
              send(parent, {ref, {:chunk, content}})
            end
          end
        
        String.starts_with?(line, "event: ") ->
          # Manejar tipos de eventos específicos si es necesario
          :ok
        
        true ->
          # Ignorar otras líneas (comentarios, etc.)
          :ok
      end
    end)
  end
end