# lib/cortex/dispatcher.ex

defmodule Cortex.Dispatcher do
  @moduledoc """
  Dispatcher principal que delega el trabajo al pool de workers.
  
  Este módulo mantiene compatibilidad hacia atrás mientras usa
  el nuevo sistema de workers internamente.
  """
  
  require Logger
  
  @doc """
  Despacha un stream de completion usando el pool de workers.
  
  Args:
    - messages: Lista de mensajes en formato OpenAI
    - opts: Opciones adicionales (modelo, etc.)
  
  Returns:
    - {:ok, stream} si puede procesar la petición
    - {:error, reason} si no hay workers disponibles
  """
  def dispatch_stream(messages, opts \\ []) do
    case Cortex.Workers.Pool.stream_completion(Cortex.Workers.Pool, messages, opts) do
      {:ok, stream} ->
        Logger.info("Stream despachado exitosamente")
        {:ok, stream}
      
      {:error, :no_workers_available} = error ->
        Logger.error("No hay workers disponibles")
        error
      
      {:error, reason} = error ->
        Logger.error("Error en dispatch_stream: #{inspect(reason)}")
        error
    end
  end
  
  @doc """
  Obtiene el estado de salud de todos los workers.
  """
  def health_status do
    Cortex.Workers.Pool.health_status()
  end
  
  @doc """
  Fuerza un health check de todos los workers.
  """
  def check_workers do
    Cortex.Workers.Pool.check_health()
  end
end
