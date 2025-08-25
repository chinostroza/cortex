defmodule Cortex.Workers.Supervisor do
  @moduledoc """
  Supervisor principal para el sistema de workers.
  
  Responsabilidades:
  - Supervisar Registry y Pool
  - Configurar workers desde configuración
  - Manejar el ciclo de vida del sistema de workers
  """
  
  use Supervisor
  
  alias Cortex.Workers.{Registry, Pool}
  alias Cortex.Workers.Adapters.OllamaWorker
  
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end
  
  @impl true
  def init(opts) do
    # Configuración por defecto
    registry_name = Keyword.get(opts, :registry_name, Cortex.Workers.Registry)
    pool_name = Keyword.get(opts, :pool_name, Cortex.Workers.Pool)
    strategy = Keyword.get(opts, :strategy, :local_first)
    
    children = [
      # Registry debe iniciarse primero
      {Registry, [name: registry_name]},
      
      # Pool depende del Registry
      {Pool, [
        name: pool_name,
        registry: registry_name,
        strategy: strategy
      ]},
      
      # Task para configurar workers iniciales
      {Task, fn -> configure_workers(registry_name) end}
    ]
    
    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.init(children, opts)
  end
  
  @doc """
  Agrega un worker al registry en tiempo de ejecución.
  """
  def add_worker(supervisor \\ __MODULE__, name, worker_opts) do
    registry_name = get_registry_name(supervisor)
    
    case worker_opts[:type] do
      :ollama ->
        worker = OllamaWorker.new(
          Keyword.put(worker_opts, :name, name)
        )
        Registry.register(registry_name, name, worker)
        
      _ ->
        {:error, :unsupported_worker_type}
    end
  end
  
  @doc """
  Remueve un worker del registry.
  """
  def remove_worker(supervisor \\ __MODULE__, name) do
    registry_name = get_registry_name(supervisor)
    Registry.unregister(registry_name, name)
  end
  
  @doc """
  Obtiene información de todos los workers.
  """
  def list_workers(supervisor \\ __MODULE__) do
    registry_name = get_registry_name(supervisor)
    Registry.list_all(registry_name)
  end
  
  # Private Functions
  
  defp configure_workers(registry_name) do
    # Leer configuración desde Application environment
    workers_config = Application.get_env(:cortex, :workers, [])
    
    # Configurar workers por defecto si no hay configuración
    default_workers = [
      %{
        name: "ollama-local",
        type: :ollama,
        base_url: "http://localhost:11434",
        models: ["gemma3:4b"]
      }
    ]
    
    workers = if Enum.empty?(workers_config), do: default_workers, else: workers_config
    
    # Registrar cada worker
    Enum.each(workers, fn worker_config ->
      case worker_config do
        %{name: name, type: :ollama} = config ->
          worker = OllamaWorker.new([
            name: name,
            base_url: Map.get(config, :base_url, "http://localhost:11434"),
            models: Map.get(config, :models, []),
            timeout: Map.get(config, :timeout, 60_000)
          ])
          
          case Registry.register(registry_name, name, worker) do
            :ok ->
              IO.puts("✅ Worker registrado: #{name}")
            {:error, :already_registered} ->
              IO.puts("⚠️  Worker ya existe: #{name}")
            error ->
              IO.puts("❌ Error registrando worker #{name}: #{inspect(error)}")
          end
          
        config ->
          IO.puts("⚠️  Configuración de worker no válida: #{inspect(config)}")
      end
    end)
  end
  
  defp get_registry_name(supervisor) do
    # Por ahora retornamos el nombre por defecto
    # En el futuro podríamos inspeccionar el supervisor para obtener el registry real
    Cortex.Workers.Registry
  end
end