defmodule Cortex.Workers.APIKeyManager do
  @moduledoc """
  Manager para rotación inteligente de API keys.
  
  Responsabilidades:
  - Detectar cuando un API key alcanza límites de rate limiting
  - Rotar automáticamente al siguiente key disponible
  - Mantener estadísticas de uso por key
  - Implementar estrategias de rotación (round-robin, least-used, etc.)
  - Manejar keys temporalmente bloqueados
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :worker_name,
    :keys_status,
    :rotation_strategy,
    :blocked_keys,
    :usage_stats
  ]
  
  @rotation_strategies [:round_robin, :least_used, :random]
  @block_duration_minutes 15  # Tiempo de bloqueo cuando se detecta rate limit
  
  # Client API
  
  def start_link(opts \\ []) do
    worker_name = Keyword.fetch!(opts, :worker_name)
    name = Keyword.get(opts, :name, :"#{worker_name}_key_manager")
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Obtiene el próximo API key disponible.
  """
  def get_next_key(manager, worker) do
    GenServer.call(manager, {:get_next_key, worker})
  end
  
  @doc """
  Reporta que un API key ha fallado por rate limiting.
  """
  def report_rate_limit(manager, worker, error_details \\ %{}) do
    GenServer.cast(manager, {:rate_limit, worker, error_details})
  end
  
  @doc """
  Reporta que un API key funcionó correctamente.
  """
  def report_success(manager, worker) do
    GenServer.cast(manager, {:success, worker})
  end
  
  @doc """
  Obtiene estadísticas de uso de todos los keys.
  """
  def get_stats(manager) do
    GenServer.call(manager, :get_stats)
  end
  
  @doc """
  Resetea el bloqueo de un key específico.
  """
  def unblock_key(manager, key_index) do
    GenServer.cast(manager, {:unblock_key, key_index})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    worker_name = Keyword.fetch!(opts, :worker_name)
    rotation_strategy = Keyword.get(opts, :rotation_strategy, :round_robin)
    
    unless rotation_strategy in @rotation_strategies do
      raise ArgumentError, "rotation_strategy debe ser uno de: #{inspect(@rotation_strategies)}"
    end
    
    state = %__MODULE__{
      worker_name: worker_name,
      keys_status: %{},
      rotation_strategy: rotation_strategy,
      blocked_keys: %{},
      usage_stats: %{}
    }
    
    # Programar limpieza periódica de keys bloqueados
    :timer.send_interval(60_000, self(), :cleanup_blocked_keys)
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get_next_key, worker}, _from, state) do
    case select_best_key(worker, state) do
      {:ok, rotated_worker} ->
        # Actualizar estadísticas
        key_index = rotated_worker.current_key_index
        new_stats = update_usage_stats(state.usage_stats, key_index, :used)
        
        {:reply, {:ok, rotated_worker}, %{state | usage_stats: new_stats}}
      
      {:error, reason} ->
        Logger.warning("No hay API keys disponibles para #{state.worker_name}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      worker_name: state.worker_name,
      rotation_strategy: state.rotation_strategy,
      total_keys: length(get_worker_keys(state)),
      blocked_keys: map_size(state.blocked_keys),
      usage_stats: state.usage_stats,
      blocked_until: state.blocked_keys
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_cast({:rate_limit, worker, _error_details}, state) do
    key_index = worker.current_key_index
    block_until = DateTime.add(DateTime.utc_now(), @block_duration_minutes, :minute)
    
    Logger.warning("API key #{key_index} para #{state.worker_name} bloqueado por rate limit hasta #{block_until}")
    
    new_blocked = Map.put(state.blocked_keys, key_index, block_until)
    new_stats = update_usage_stats(state.usage_stats, key_index, :rate_limited)
    
    {:noreply, %{state | blocked_keys: new_blocked, usage_stats: new_stats}}
  end
  
  @impl true
  def handle_cast({:success, worker}, state) do
    key_index = worker.current_key_index
    new_stats = update_usage_stats(state.usage_stats, key_index, :success)
    
    {:noreply, %{state | usage_stats: new_stats}}
  end
  
  @impl true
  def handle_cast({:unblock_key, key_index}, state) do
    new_blocked = Map.delete(state.blocked_keys, key_index)
    Logger.info("API key #{key_index} para #{state.worker_name} desbloqueado manualmente")
    
    {:noreply, %{state | blocked_keys: new_blocked}}
  end
  
  @impl true
  def handle_info(:cleanup_blocked_keys, state) do
    now = DateTime.utc_now()
    
    # Filtrar keys que ya no están bloqueados
    still_blocked = state.blocked_keys
    |> Enum.filter(fn {_key_index, block_until} ->
      DateTime.compare(now, block_until) == :lt
    end)
    |> Map.new()
    
    # Log keys que fueron desbloqueados
    unblocked_count = map_size(state.blocked_keys) - map_size(still_blocked)
    if unblocked_count > 0 do
      Logger.info("#{unblocked_count} API keys para #{state.worker_name} desbloqueados automáticamente")
    end
    
    {:noreply, %{state | blocked_keys: still_blocked}}
  end
  
  # Private Functions
  
  defp select_best_key(worker, state) do
    available_keys = get_available_keys(worker, state)
    
    case available_keys do
      [] ->
        {:error, :no_available_keys}
      
      keys ->
        selected_index = apply_rotation_strategy(keys, state)
        rotated_worker = %{worker | current_key_index: selected_index}
        {:ok, rotated_worker}
    end
  end
  
  defp get_available_keys(worker, state) do
    api_keys = Map.get(worker, :api_keys, [])
    total_keys = length(api_keys)
    
    if total_keys > 0 do
      0..(total_keys - 1)
      |> Enum.reject(fn key_index ->
        Map.has_key?(state.blocked_keys, key_index)
      end)
    else
      []
    end
  end
  
  defp apply_rotation_strategy(available_keys, %{rotation_strategy: :round_robin} = state) do
    # Obtener el último key usado desde las estadísticas
    last_used = get_last_used_key(state.usage_stats)
    
    # Encontrar el siguiente key en orden circular
    current_index = Enum.find_index(available_keys, &(&1 == last_used)) || 0
    next_index = rem(current_index + 1, length(available_keys))
    Enum.at(available_keys, next_index)
  end
  
  defp apply_rotation_strategy(available_keys, %{rotation_strategy: :least_used} = state) do
    # Seleccionar el key con menos uso
    available_keys
    |> Enum.min_by(fn key_index ->
      get_key_usage_count(state.usage_stats, key_index)
    end)
  end
  
  defp apply_rotation_strategy(available_keys, %{rotation_strategy: :random}) do
    Enum.random(available_keys)
  end
  
  defp get_worker_keys(%{worker_name: worker_name}) do
    # Esta función necesitaría acceso al Registry para obtener el worker
    # Por simplicidad, asumimos que tenemos acceso
    case Cortex.Workers.Registry.get(worker_name) do
      {:ok, worker} -> worker.api_keys
      {:error, _} -> []
    end
  end
  
  defp update_usage_stats(stats, key_index, event) do
    key_stats = Map.get(stats, key_index, %{
      used: 0,
      success: 0,
      rate_limited: 0,
      last_used: nil
    })
    
    updated_stats = case event do
      :used ->
        %{key_stats | 
          used: key_stats.used + 1,
          last_used: DateTime.utc_now()
        }
      
      :success ->
        %{key_stats | success: key_stats.success + 1}
      
      :rate_limited ->
        %{key_stats | rate_limited: key_stats.rate_limited + 1}
    end
    
    Map.put(stats, key_index, updated_stats)
  end
  
  defp get_last_used_key(stats) do
    stats
    |> Enum.max_by(fn {_key_index, key_stats} ->
      key_stats[:last_used] || DateTime.from_unix!(0)
    end, fn -> {0, %{}} end)
    |> elem(0)
  end
  
  defp get_key_usage_count(stats, key_index) do
    case Map.get(stats, key_index) do
      nil -> 0
      key_stats -> key_stats[:used] || 0
    end
  end
end