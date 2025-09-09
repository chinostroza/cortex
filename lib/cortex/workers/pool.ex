defmodule Cortex.Workers.Pool do
  @moduledoc """
  Pool de workers que gestiona la selección y distribución de trabajo.
  
  Responsabilidades:
  - Seleccionar el mejor worker disponible según la estrategia
  - Ejecutar health checks periódicos
  - Manejar failover cuando un worker falla
  - Implementar diferentes estrategias de routing
  """
  
  use GenServer
  require Logger
  
  @health_check_interval 30_000  # 30 segundos
  
  defstruct [
    :registry,
    :strategy,
    :health_status,
    :check_interval,
    :round_robin_index
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Obtiene un stream de completion del mejor worker disponible.
  Si el primer worker falla, intenta con el siguiente.
  """
  def stream_completion(pool \\ __MODULE__, messages, opts \\ []) do
    GenServer.call(pool, {:stream_completion, messages, opts}, 30_000)
  end
  
  @doc """
  Obtiene el estado de salud de todos los workers.
  """
  def health_status(pool \\ __MODULE__) do
    GenServer.call(pool, :health_status)
  end
  
  @doc """
  Fuerza un health check inmediato de todos los workers.
  """
  def check_health(pool \\ __MODULE__) do
    GenServer.cast(pool, :check_health)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    registry = Keyword.get(opts, :registry, Cortex.Workers.Registry)
    strategy = Keyword.get(opts, :strategy, :local_first)
    check_interval = Keyword.get(opts, :check_interval, @health_check_interval)
    
    state = %__MODULE__{
      registry: registry,
      strategy: strategy,
      health_status: %{},
      check_interval: check_interval,
      round_robin_index: 0
    }
    
    # Programar configuración de workers y primer health check
    Process.send_after(self(), :configure_initial_workers, 500)
    
    # Solo programar health checks si están habilitados
    if check_interval != :disabled do
      Process.send_after(self(), :periodic_health_check, 2000)
    end
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:stream_completion, messages, opts}, _from, state) do
    case select_and_execute(state, messages, opts) do
      {:ok, stream, new_state} ->
        {:reply, {:ok, stream}, new_state}
      
      {:ok, stream} ->
        {:reply, {:ok, stream}, state}
      
      {:error, :no_workers_available} = error ->
        Logger.error("No hay workers disponibles")
        {:reply, error, state}
      
      {:error, reason} = error ->
        Logger.error("Error al procesar completion: #{inspect(reason)}")
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call(:health_status, _from, state) do
    {:reply, state.health_status, state}
  end
  
  @impl true
  def handle_cast(:check_health, state) do
    new_health_status = perform_health_checks(state)
    {:noreply, %{state | health_status: new_health_status}}
  end
  
  @impl true
  def handle_info(:configure_initial_workers, state) do
    # Configurar workers de forma asíncrona
    Task.start(fn ->
      Cortex.Workers.Supervisor.configure_initial_workers(state.registry)
    end)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:periodic_health_check, state) do
    new_health_status = perform_health_checks(state)
    
    # Programar el siguiente check solo si no están deshabilitados
    if state.check_interval != :disabled do
      Process.send_after(self(), :periodic_health_check, state.check_interval)
    end
    
    {:noreply, %{state | health_status: new_health_status}}
  end
  
  # Private Functions
  
  defp select_and_execute(state, messages, opts) do
    # Verificar si se especificó un provider
    case Keyword.get(opts, :provider) do
      nil ->
        # Usar estrategia normal de selección
        case state.strategy do
          :round_robin ->
            workers = get_available_workers(state)
            case execute_with_workers(workers, messages, opts) do
              {:ok, stream} ->
                # Incrementar el índice para la siguiente llamada
                new_state = %{state | round_robin_index: state.round_robin_index + 1}
                {:ok, stream, new_state}
              error -> error
            end
          _ ->
            workers = get_available_workers(state)
            execute_with_workers(workers, messages, opts)
        end
      
      provider ->
        # Usar worker específico
        workers = get_workers_by_provider(state, provider)
        execute_with_workers(workers, messages, opts)
    end
  end
  
  defp execute_with_workers([], _messages, _opts) do
    {:error, :no_workers_available}
  end
  
  defp execute_with_workers(workers, messages, opts) do
    # Intentar con cada worker hasta que uno funcione
    execute_with_failover(workers, messages, opts)
  end
  
  defp get_available_workers(state) do
    all_workers = if is_pid(state.registry) do
      GenServer.call(state.registry, :list_all)
    else
      apply(state.registry, :list_all, [])
    end
    
    # Filtrar solo workers disponibles
    available = all_workers
    |> Enum.filter(fn worker ->
      worker_name = worker.name
      health = Map.get(state.health_status, worker_name, :unknown)
      # Considerar workers unknown como disponibles inicialmente
      health == :available or health == :unknown
    end)
    
    # Ordenar según la estrategia
    Logger.info("Using strategy: #{inspect(state.strategy)}")
    case state.strategy do
      :round_robin -> apply_round_robin_strategy(available, state)
      _ -> apply_strategy(available, state.strategy)
    end
  end
  
  defp apply_strategy(workers, :local_first) do
    # Ordenar por prioridad (menor número = mayor prioridad)
    Enum.sort_by(workers, fn worker ->
      apply(worker.__struct__, :priority, [worker])
    end)
  end
  
  defp apply_strategy(workers, :round_robin) do
    # Esta función no se usa para round_robin, se maneja en apply_round_robin_strategy
    Enum.shuffle(workers)
  end
  
  defp apply_strategy(workers, _), do: workers
  
  defp apply_round_robin_strategy(workers, state) do
    # Implementar round-robin real con estado
    if Enum.empty?(workers) do
      []
    else
      # Ordenar workers por nombre para consistencia
      sorted_workers = Enum.sort_by(workers, & &1.name)
      
      # Obtener el índice actual y rotar
      current_index = rem(state.round_robin_index, length(sorted_workers))
      
      # Rotar la lista para que el worker actual esté primero
      {front, back} = Enum.split(sorted_workers, current_index)
      rotated = back ++ front
      
      # Debug logging
      worker_names = Enum.map(sorted_workers, & &1.name)
      rotated_names = Enum.map(rotated, & &1.name)
      Logger.info("Round-robin: workers=#{inspect(worker_names)}, index=#{current_index}, rotated=#{inspect(rotated_names)}")
      
      rotated
    end
  end
  
  defp execute_with_failover([], _messages, _opts) do
    {:error, :all_workers_failed}
  end
  
  defp execute_with_failover([worker | rest], messages, opts) do
    Logger.info("Intentando con worker: #{worker.name}")
    
    case apply(worker.__struct__, :stream_completion, [worker, messages, opts]) do
      {:ok, stream} ->
        # Verificar que el stream no esté vacío
        case validate_stream(stream) do
          :ok ->
            Logger.info("Worker #{worker.name} respondió exitosamente")
            {:ok, stream}
          {:error, :empty_stream} ->
            Logger.warning("Worker #{worker.name} devolvió stream vacío, intentando con siguiente worker")
            execute_with_failover(rest, messages, opts)
        end
      
      {:error, reason} ->
        Logger.warning("Worker #{worker.name} falló: #{inspect(reason)}")
        execute_with_failover(rest, messages, opts)
    end
  end
  
  defp perform_health_checks(state) do
    workers = if is_pid(state.registry) do
      GenServer.call(state.registry, :list_all)
    else
      apply(state.registry, :list_all, [])
    end
    
    # Ejecutar health checks en paralelo
    tasks = Enum.map(workers, fn worker ->
      Task.async(fn ->
        status = case apply(worker.__struct__, :health_check, [worker]) do
          {:ok, status} -> status
          {:error, _} -> :unavailable
        end
        
        {worker.name, status}
      end)
    end)
    
    # Recolectar resultados con timeout
    results = tasks
    |> Task.yield_many(5000)
    |> Enum.map(fn {task, result} ->
      case result do
        {:ok, value} -> value
        _ ->
          Task.shutdown(task, :brutal_kill)
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
    
    Logger.info("Health check completado: #{inspect(results)}")
    results
  end

  defp validate_stream(stream) do
    # Intentar leer el primer chunk del stream para verificar que no esté vacío
    case Stream.take(stream, 1) |> Enum.to_list() do
      [] ->
        {:error, :empty_stream}
      [_first_chunk | _] ->
        :ok
    end
  rescue
    # Si hay error al leer el stream, considerarlo como vacío
    _ ->
      {:error, :empty_stream}
  end

  defp get_workers_by_provider(state, provider) do
    all_workers = if is_pid(state.registry) do
      GenServer.call(state.registry, :list_all)
    else
      apply(state.registry, :list_all, [])
    end
    
    # Filtrar por provider y disponibilidad
    all_workers
    |> Enum.filter(fn worker ->
      worker_name = worker.name
      health = Map.get(state.health_status, worker_name, :unknown)
      
      # Verificar que esté disponible y coincida con el provider
      health == :available and String.contains?(worker_name, provider)
    end)
  end
end
