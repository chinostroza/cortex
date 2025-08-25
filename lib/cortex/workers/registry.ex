defmodule Cortex.Workers.Registry do
  @moduledoc """
  Registry que mantiene el registro de todos los workers disponibles.
  
  Responsabilidades:
  - Registrar y desregistrar workers
  - Buscar workers por nombre o tipo
  - Listar workers disponibles
  """
  
  use GenServer
  
  # Client API
  
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end
  
  @doc """
  Registra un nuevo worker en el registry.
  """
  def register(registry \\ __MODULE__, name, worker) do
    GenServer.call(registry, {:register, name, worker})
  end
  
  @doc """
  Desregistra un worker del registry.
  """
  def unregister(registry \\ __MODULE__, name) do
    GenServer.call(registry, {:unregister, name})
  end
  
  @doc """
  Obtiene un worker por su nombre.
  """
  def get(registry \\ __MODULE__, name) do
    GenServer.call(registry, {:get, name})
  end
  
  @doc """
  Lista todos los workers registrados.
  """
  def list_all(registry \\ __MODULE__) do
    GenServer.call(registry, :list_all)
  end
  
  @doc """
  Lista workers de un tipo específico.
  """
  def list_by_type(registry \\ __MODULE__, type) do
    GenServer.call(registry, {:list_by_type, type})
  end
  
  @doc """
  Obtiene el conteo de workers registrados.
  """
  def count(registry \\ __MODULE__) do
    GenServer.call(registry, :count)
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    {:ok, %{workers: %{}}}
  end
  
  @impl true
  def handle_call({:register, name, worker}, _from, state) do
    case Map.get(state.workers, name) do
      nil ->
        new_workers = Map.put(state.workers, name, worker)
        {:reply, :ok, %{state | workers: new_workers}}
      
      _existing ->
        {:reply, {:error, :already_registered}, state}
    end
  end
  
  @impl true
  def handle_call({:unregister, name}, _from, state) do
    new_workers = Map.delete(state.workers, name)
    {:reply, :ok, %{state | workers: new_workers}}
  end
  
  @impl true
  def handle_call({:get, name}, _from, state) do
    case Map.get(state.workers, name) do
      nil -> {:reply, {:error, :not_found}, state}
      worker -> {:reply, {:ok, worker}, state}
    end
  end
  
  @impl true
  def handle_call(:list_all, _from, state) do
    workers = Map.values(state.workers)
    {:reply, workers, state}
  end
  
  @impl true
  def handle_call({:list_by_type, type}, _from, state) do
    workers = state.workers
    |> Map.values()
    |> Enum.filter(fn worker ->
      worker_info = apply(worker.__struct__, :info, [worker])
      worker_info[:type] == type
    end)
    
    {:reply, workers, state}
  end
  
  @impl true
  def handle_call(:count, _from, state) do
    count = map_size(state.workers)
    {:reply, count, state}
  end
end