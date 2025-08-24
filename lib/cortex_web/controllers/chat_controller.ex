# en lib/cortex_web/controllers/chat_controller.ex

defmodule CortexWeb.ChatController do
  use CortexWeb, :controller

  def create(conn, %{"messages" => messages}) do
    case Cortex.Dispatcher.dispatch(messages) do
      {:ok, full_response_body} ->
        conn = send_chunked(conn, 200)

        # Usamos Enum.reduce para procesar cada línea de la respuesta
        Enum.reduce(String.split(full_response_body, "\n", trim: true), conn, fn line, acc_conn ->
          content =
            case Jason.decode(line) do
              {:ok, %{"message" => %{"content" => c}}} -> c
              _ -> ""
            end

          # La corrección clave está aquí.
          # Plug.Conn.chunk/2 devuelve {:ok, conn}, por lo que debemos
          # extraer la `conn` para pasarla a la siguiente iteración.
          {:ok, new_conn} = Plug.Conn.chunk(acc_conn, content)
          new_conn
        end)

      {:error, reason} ->
        IO.inspect(reason, label: "Error en Dispatcher")
        send_resp(conn, 500, "Error interno del servidor")
    end
  end
end
