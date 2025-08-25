# en lib/cortex_web/controllers/chat_controller.ex

defmodule CortexWeb.ChatController do
  use CortexWeb, :controller

  def create(conn, %{"messages" => messages}) do
    case Cortex.Dispatcher.dispatch_stream(messages) do
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

      {:error, reason} ->
        IO.inspect(reason, label: "Error en Dispatcher")
        send_resp(conn, 500, "Error interno del servidor")
    end
  end
end
