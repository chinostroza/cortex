# en lib/cortex_web/controllers/chat_controller.ex

defmodule CortexWeb.ChatController do
  use CortexWeb, :controller

  def create(conn, %{"messages" => messages}) do
    case Cortex.Dispatcher.dispatch_stream(messages) do
      {:ok, stream_body} ->
        conn = send_chunked(conn, 200)

        # Iteramos directamente sobre el cuerpo del stream
        final_conn = Enum.reduce(stream_body, conn, fn chunk, acc_conn ->
          content =
            case Jason.decode(chunk) do
              {:ok, %{"message" => %{"content" => c}}} -> c
              _ -> ""
            end

          if content != "" do
            {:ok, new_conn} = Plug.Conn.chunk(acc_conn, content)
            new_conn
          else
            acc_conn
          end
        end)
        
        # Cerrar explícitamente la conexión chunked
        final_conn

      {:error, :no_workers_available} ->
        send_resp(conn, 503, "No hay workers de IA disponibles en este momento")

      {:error, reason} ->
        IO.inspect(reason, label: "Error en Dispatcher")
        send_resp(conn, 500, "Error interno del servidor")
    end
  end
end
