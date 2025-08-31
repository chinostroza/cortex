defmodule Cortex.Workers.Adapters.APIWorkerBase do
  @moduledoc """
  Módulo base para workers de APIs externas.
  
  Proporciona funcionalidades comunes para reducir duplicación de código:
  - Manejo de API keys
  - Construcción de headers HTTP
  - Manejo de timeouts y errores comunes
  - Streaming con Server-Sent Events (SSE) y JSON arrays (Gemini)
  """
  
  @callback provider_config(worker :: struct()) :: map()
  @callback transform_messages(messages :: list(), opts :: keyword()) :: term()
  @callback extract_content_from_chunk(chunk :: String.t()) :: String.t()
  
  def health_check(worker) do
    config = apply(worker.__struct__, :provider_config, [worker])
    
    health_url = Map.get(config, :health_endpoint, config.base_url)
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
  
  def stream_completion(worker, messages, opts) do
    config = apply(worker.__struct__, :provider_config, [worker])
    
    transformed_messages = apply(worker.__struct__, :transform_messages, [messages, opts])
    payload = build_payload(worker, transformed_messages, config, opts)
    
    url = config.base_url <> config.stream_endpoint
    headers = apply(config.headers_fn, [worker])
    
    request = Finch.build(
      :post,
      url,
      [{"content-type", "application/json"} | headers],
      Jason.encode!(payload)
    )
    
    stream = create_sse_stream(request, worker)
    {:ok, stream}
  rescue
    error -> {:error, error}
  end
  
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
    
    # Para Gemini, messages ya viene transformado con el formato correcto
    base_payload = if is_map(messages) and Map.has_key?(messages, "contents") do
      # Gemini format - usar directamente
      messages
    else
      # OpenAI format - usar formato estándar
      %{
        config.model_param => model,
        "messages" => messages,
        "stream" => true
      }
    end
    
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
              # Procesar Server-Sent Events o JSON arrays
              process_streaming_data(data, parent, ref, worker)
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
  
  defp process_streaming_data(data, parent, ref, worker) do
    # Detectar si es Gemini para usar formato JSON array
    if String.contains?(worker.name, "gemini") do
      process_gemini_json_stream(data, parent, ref, worker)
    else
      process_sse_data(data, parent, ref, worker)
    end
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
  
  defp process_gemini_json_stream(data, parent, ref, worker) do
    # Gemini retorna JSON directamente, no SSE
    case Jason.decode(data) do
      {:ok, _json_response} ->
        content = apply(worker.__struct__, :extract_content_from_chunk, [data])
        if content != "" do
          send(parent, {ref, {:chunk, content}})
        end
      
      {:error, _} ->
        # Si no es JSON válido, ignorar
        :ok
    end
  end
end