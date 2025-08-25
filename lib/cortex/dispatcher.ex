# en lib/cortex/dispatcher.ex

defmodule Cortex.Dispatcher do
  @ollama_url "http://localhost:11434"

  def dispatch_stream(messages) do
    payload = %{
      model: "gemma3:4b",
      messages: messages,
      stream: true
    }

    # Construir el request con Finch
    request = Finch.build(
      :post,
      @ollama_url <> "/api/chat",
      [{"content-type", "application/json"}],
      Jason.encode!(payload)
    )

    # Crear un stream que consume los datos de Finch
    stream = Stream.unfold(:init, fn
      :init ->
        # Crear un proceso que recolecte los chunks
        parent = self()
        ref = make_ref()
        
        spawn(fn ->
          Finch.stream(request, Req.Finch, "", fn
            {:status, _status}, acc -> 
              acc
            {:headers, _headers}, acc -> 
              acc
            {:data, data}, acc ->
              # Procesar cada línea individualmente
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
          {^ref, :done} -> 
            nil
          {^ref, {:chunk, chunk}} -> 
            {chunk, state}
        after
          30_000 -> nil
        end
        
      _ ->
        nil
    end)
    |> Stream.reject(&is_nil/1)
    
    {:ok, stream}
  end
end
