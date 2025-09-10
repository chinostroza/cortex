# en lib/cortex_web/controllers/chat_controller.ex

defmodule CortexWeb.ChatController do
  use CortexWeb, :controller

  def create(conn, params) do
    messages = Map.get(params, "messages")
    
    unless messages do
      send_resp(conn, 400, "Missing required field: messages")
    else
      # Extraer parámetros opcionales
      opts = extract_options(params)
      
      case Cortex.Dispatcher.dispatch_stream(messages, opts) do
        {:ok, stream_body} ->
          conn = send_chunked(conn, 200)

          # Procesar el stream correctamente con try/catch para manejar errores
          try do
            Enum.reduce_while(stream_body, conn, fn chunk, acc_conn ->
              case chunk do
                nil -> {:halt, acc_conn}  # Fin del stream
                data when is_binary(data) ->
                  # Intentar parsear JSON
                  content = case Jason.decode(data) do
                    {:ok, %{"choices" => [%{"delta" => %{"content" => c}}]}} when is_binary(c) -> c
                    {:ok, %{"message" => %{"content" => c}}} when is_binary(c) -> c
                    {:ok, %{"content" => c}} when is_binary(c) -> c
                    _ -> 
                      # Si no es JSON válido, enviar tal como está
                      if String.printable?(data), do: data, else: ""
                  end

                  if content != "" do
                    case Plug.Conn.chunk(acc_conn, content) do
                      {:ok, new_conn} -> {:cont, new_conn}
                      {:error, _} -> {:halt, acc_conn}
                    end
                  else
                    {:cont, acc_conn}
                  end
                _ ->
                  {:cont, acc_conn}  # Ignorar chunks no válidos
              end
            end)
          rescue
            error ->
              IO.inspect(error, label: "Error procesando stream")
              conn
          end

        {:error, :no_workers_available} ->
          send_resp(conn, 503, "No hay workers de IA disponibles en este momento")
          
        {:error, {:all_workers_failed, detailed_errors}} ->
          IO.inspect(detailed_errors, label: "Error en Dispatcher")
          error_response = %{
            "error" => "All AI providers failed",
            "details" => detailed_errors,
            "message" => "No se pudo procesar la solicitud. Detalles: #{detailed_errors}"
          }
          json(conn |> put_status(500), error_response)

        {:error, reason} ->
          IO.inspect(reason, label: "Error en Dispatcher")
          error_response = %{
            "error" => "Internal server error",
            "message" => "Error interno del servidor: #{inspect(reason)}"
          }
          json(conn |> put_status(500), error_response)
      end
    end
  end
  
  # Extraer opciones del request
  defp extract_options(params) do
    opts = []
    
    # Modelo específico
    opts = if model = params["model"] do
      Keyword.put(opts, :model, model)
    else
      opts
    end
    
    # Provider específico
    opts = if provider = params["provider"] do
      Keyword.put(opts, :provider, provider)
    else
      opts
    end
    
    # Temperature
    opts = if temp = params["temperature"] do
      Keyword.put(opts, :temperature, temp)
    else
      opts
    end
    
    # Max tokens
    opts = if max_tokens = params["max_tokens"] do
      Keyword.put(opts, :max_tokens, max_tokens)
    else
      opts
    end
    
    opts
  end
end