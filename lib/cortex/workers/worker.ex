defmodule Cortex.Workers.Worker do
  @moduledoc """
  Behaviour que define el contrato para todos los workers de IA.
  
  Cada worker debe implementar las funciones necesarias para:
  - Verificar su disponibilidad (health check)
  - Procesar mensajes y devolver un stream
  - Reportar su información y capacidades
  """

  @doc """
  Verifica si el worker está disponible y funcionando.
  
  El worker recibe su propia struct como argumento.
  
  Returns:
    - {:ok, :available} si el worker está listo
    - {:ok, :busy} si está ocupado pero funcional
    - {:error, reason} si hay algún problema
  """
  @callback health_check(worker :: struct()) :: {:ok, :available | :busy} | {:error, term()}

  @doc """
  Procesa una lista de mensajes y devuelve un stream de respuestas.
  
  Args:
    - worker: La struct del worker
    - messages: Lista de mensajes con formato [%{role: String.t(), content: String.t()}]
    - opts: Opciones adicionales (modelo, temperatura, etc.)
  
  Returns:
    - {:ok, stream} donde stream es un Stream que emite chunks de texto
    - {:error, reason} si no puede procesar la petición
  """
  @callback stream_completion(worker :: struct(), messages :: list(map()), opts :: keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}

  @doc """
  Devuelve información sobre el worker.
  
  Args:
    - worker: La struct del worker
  
  Returns:
    - Mapa con información del worker (nombre, tipo, modelos soportados, etc.)
  """
  @callback info(worker :: struct()) :: map()

  @doc """
  Devuelve la prioridad del worker (menor número = mayor prioridad).
  Usado para ordenar workers cuando hay múltiples disponibles.
  
  Args:
    - worker: La struct del worker
  """
  @callback priority(worker :: struct()) :: integer()
end