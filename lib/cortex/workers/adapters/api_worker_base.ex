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
      {:ok, %{status: 429, body: body}} ->
        # Detectar cuota agotada específicamente
        if quota_exceeded?(body) do
          {:error, {:quota_exceeded, "API quota exceeded - temporarily unavailable"}}
        else
          {:error, {:rate_limited, "Rate limited - retry later"}}
        end
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
  
  defp quota_exceeded?(body) when is_binary(body) do
    # Patrones comunes de cuota agotada
    quota_patterns = [
      "quota",
      "exceeded",
      "billing",
      "plan", 
      "current quota",
      "rate limit exceeded"
    ]
    
    body_lower = String.downcase(body)
    Enum.any?(quota_patterns, fn pattern -> 
      String.contains?(body_lower, pattern)
    end)
  end
  
  defp quota_exceeded?(_), do: false
  
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
    
    # Manejar diferentes formatos de providers
    base_payload = cond do
      # Gemini format - usar directamente  
      is_map(messages) and Map.has_key?(messages, "contents") ->
        messages
      
      # Anthropic format - messages ya transformado, agregar model y stream
      is_map(messages) and Map.has_key?(messages, "messages") ->
        Map.merge(messages, %{
          config.model_param => model,
          "stream" => true
        })
      
      # OpenAI format - usar formato estándar
      true ->
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
          # Capturar el estado de la respuesta HTTP
          response_state = %{status: nil, has_error: false, error_body: ""}
          
          result = Finch.stream(request, Req.Finch, response_state, fn
            {:status, status}, acc ->
              if status >= 400 do
                %{acc | has_error: true, status: status}
              else
                %{acc | status: status}
              end
              
            {:headers, _headers}, acc -> acc
            
            {:data, data}, acc ->
              if acc.has_error do
                # Capturar el mensaje de error del cuerpo de la respuesta
                new_error_body = acc.error_body <> data
                updated_acc = %{acc | error_body: new_error_body}
                
                # Solo enviar el error una vez cuando tenemos el mensaje completo
                if String.contains?(new_error_body, "}") or String.contains?(new_error_body, "\n") do
                  error_message = extract_error_message(new_error_body, acc.status)
                  require Logger
                  Logger.error("HTTP #{acc.status} error from #{worker.name}: #{error_message}")
                  send(parent, {ref, {:error, {acc.status, error_message}}})
                end
                
                updated_acc
              else
                # Procesar datos normales
                process_streaming_data(data, parent, ref, worker)
                acc
              end
          end)
          
          # Si hubo error en la conexión
          case result do
            {:error, reason} ->
              require Logger
              Logger.error("Error de conexión en #{worker.name}: #{inspect(reason)}")
              send(parent, {ref, {:error, :connection_error}})
            _ ->
              :ok
          end
          
          send(parent, {ref, :done})
        end)
        
        {nil, {ref, :streaming}}
        
      {ref, :streaming} = state ->
        receive do
          {^ref, :done} -> nil
          {^ref, {:error, {http_status, message}}} when is_integer(http_status) -> 
            require Logger
            Logger.error("Stream terminado por HTTP #{http_status} en #{worker.name}: #{message}")
            nil
          {^ref, {:error, http_status}} when is_integer(http_status) -> 
            require Logger
            Logger.error("Stream terminado por HTTP #{http_status} en #{worker.name}")
            nil
          {^ref, {:error, reason}} -> 
            require Logger
            Logger.error("Stream error en #{worker.name}: #{inspect(reason)}")
            nil
          {^ref, {:chunk, chunk}} -> {chunk, state}
        after
          worker.timeout -> 
            require Logger
            Logger.warning("Timeout en stream de #{worker.name}")
            nil
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
  
  # Función privada para extraer mensaje de error del cuerpo de respuesta
  defp extract_error_message(error_body, status_code) do
    # Intentar parsear como JSON primero
    case Jason.decode(error_body) do
      {:ok, %{"error" => %{"message" => message}}} -> message
      {:ok, %{"error" => message}} when is_binary(message) -> message
      {:ok, %{"message" => message}} -> message
      {:ok, %{"detail" => detail}} -> detail
      {:ok, %{"errors" => errors}} when is_list(errors) -> 
        errors |> Enum.map(&Map.get(&1, "message", &1)) |> Enum.join(", ")
      _ ->
        # Si no es JSON válido, usar texto plano (limpiar HTML si existe)
        clean_text = error_body
        |> String.replace(~r/<[^>]+>/, "")
        |> String.trim()
        
        if String.length(clean_text) > 200 do
          String.slice(clean_text, 0, 200) <> "..."
        else
          case clean_text do
            "" -> get_default_error_message(status_code)
            text -> text
          end
        end
    end
  rescue
    _ -> get_default_error_message(status_code)
  end
  
  defp get_default_error_message(413), do: "Request too large - reduce message size"
  defp get_default_error_message(503), do: "Service temporarily unavailable"
  defp get_default_error_message(429), do: "Rate limit exceeded - try again later"
  defp get_default_error_message(401), do: "Invalid API key"
  defp get_default_error_message(403), do: "Access forbidden - check permissions"
  defp get_default_error_message(500), do: "Internal server error"
  defp get_default_error_message(code), do: "HTTP #{code} error"
end