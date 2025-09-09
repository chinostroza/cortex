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
  alias Cortex.Workers.Adapters.{OllamaWorker, GroqWorker, GeminiWorker, CohereWorker}
  
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end
  
  @impl true
  def init(opts) do
    # Configuración por defecto
    registry_name = Keyword.get(opts, :registry_name, Cortex.Workers.Registry)
    pool_name = Keyword.get(opts, :pool_name, Cortex.Workers.Pool)
    
    # Leer estrategia desde environment variable
    env_strategy = System.get_env("WORKER_POOL_STRATEGY", "local_first")
    strategy = case env_strategy do
      "round_robin" -> :round_robin
      "least_used" -> :least_used
      "random" -> :random
      _ -> :local_first
    end
    
    IO.puts("🎯 Pool strategy configurada: #{inspect(strategy)} (desde env: #{env_strategy})")
    
    # Leer intervalo de health check desde environment
    health_check_interval = case System.get_env("HEALTH_CHECK_INTERVAL") do
      nil -> 30_000  # 30 segundos por defecto
      "0" -> :disabled  # Deshabilitar health checks
      interval_str ->
        case Integer.parse(interval_str) do
          {seconds, ""} -> seconds * 1000  # Convertir a milliseconds
          _ -> 30_000
        end
    end
    
    children = [
      # Registry debe iniciarse primero
      {Registry, [name: registry_name]},
      
      # Pool depende del Registry
      {Pool, [
        name: pool_name,
        registry: registry_name,
        strategy: strategy,
        check_interval: health_check_interval
      ]},
      
      # Task SUPERVISOR para configurar workers de forma asíncrona
      {Task.Supervisor, name: Cortex.Workers.TaskSupervisor}
    ]
    
    # El Pool se encargará de configurar workers cuando esté listo
    
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
        
      :groq ->
        worker = GroqWorker.new(
          Keyword.put(worker_opts, :name, name)
        )
        Registry.register(registry_name, name, worker)
        
      :gemini ->
        worker = GeminiWorker.new(
          Keyword.put(worker_opts, :name, name)
        )
        Registry.register(registry_name, name, worker)
        
      :cohere ->
        worker = CohereWorker.new(
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
  
  @doc """
  Configura workers iniciales. Llamado de forma asíncrona por el Pool.
  """
  def configure_initial_workers(registry_name) do
    configure_workers(registry_name)
  end
  
  # Private Functions
  
  defp configure_workers(registry_name) do
    # Configurar workers desde variables de entorno
    # Configurar workers desde variables de entorno
    workers_to_register = 
      []
      |> maybe_add_groq_worker()
      |> maybe_add_gemini_worker()  
      |> maybe_add_cohere_worker()
      |> maybe_add_ollama_worker()
    
    # Registrar todos los workers configurados
    Enum.each(workers_to_register, fn {name, worker} ->
      case Registry.register(registry_name, name, worker) do
        :ok ->
          IO.puts("✅ Worker registrado: #{name}")
        {:error, :already_registered} ->
          IO.puts("⚠️  Worker ya existe: #{name}")
        error ->
          IO.puts("❌ Error registrando worker #{name}: #{inspect(error)}")
      end
    end)
    
    # Mostrar resumen de workers configurados
    if Enum.empty?(workers_to_register) do
      IO.puts("⚠️  No se encontraron API keys válidos. Revisa tu archivo .env")
    else
      IO.puts("🚀 Configurados #{length(workers_to_register)} workers: #{Enum.map(workers_to_register, &elem(&1, 0)) |> Enum.join(", ")}")
    end
  end
  
  # Función auxiliar para parsear listas de API keys desde environment
  defp get_env_list(env_var) do
    case System.get_env(env_var) do
      nil -> []
      "" -> []
      keys_string -> 
        keys_string
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end
  
  defp maybe_add_groq_worker(workers) do
    groq_keys = get_env_list("GROQ_API_KEYS")
    if not Enum.empty?(groq_keys) do
      groq_model = System.get_env("GROQ_MODEL", "llama-3.1-8b-instant")
      worker = GroqWorker.new([
        name: "groq-primary",
        api_keys: groq_keys,
        model: groq_model,
        timeout: 30_000
      ])
      [{"groq-primary", worker} | workers]
    else
      workers
    end
  end
  
  defp maybe_add_gemini_worker(workers) do
    gemini_keys = get_env_list("GEMINI_API_KEYS")
    if not Enum.empty?(gemini_keys) do
      gemini_model = System.get_env("GEMINI_MODEL", "gemini-2.0-flash-001")
      worker = GeminiWorker.new([
        name: "gemini-primary",
        api_keys: gemini_keys,
        model: gemini_model,
        timeout: 30_000
      ])
      [{"gemini-primary", worker} | workers]
    else
      workers
    end
  end
  
  defp maybe_add_cohere_worker(workers) do
    cohere_keys = get_env_list("COHERE_API_KEYS")
    if not Enum.empty?(cohere_keys) do
      cohere_model = System.get_env("COHERE_MODEL", "command-light")
      worker = CohereWorker.new([
        name: "cohere-primary",
        api_keys: cohere_keys,
        model: cohere_model,
        timeout: 30_000
      ])
      [{"cohere-primary", worker} | workers]
    else
      workers
    end
  end
  
  defp maybe_add_ollama_worker(workers) do
    # Ollama siempre está disponible como local fallback  
    ollama_url = System.get_env("OLLAMA_BASE_URL", "http://localhost:11434")
    ollama_model = System.get_env("OLLAMA_MODEL", "gemma3:4b")
    
    # Verificar si Ollama está corriendo
    case check_ollama_availability(ollama_url) do
      true ->
        worker = OllamaWorker.new([
          name: "ollama-local", 
          base_url: ollama_url,
          models: [ollama_model],
          timeout: 60_000  # Ollama puede ser más lento
        ])
        [{"ollama-local", worker} | workers]
      false ->
        IO.puts("⚠️  Ollama no disponible en #{ollama_url}")
        workers
    end
  end
  
  defp check_ollama_availability(base_url) do
    case Req.get(base_url <> "/api/tags", receive_timeout: 2000) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end
  
  defp get_registry_name(_supervisor) do
    # Por ahora retornamos el nombre por defecto
    # En el futuro podríamos inspeccionar el supervisor para obtener el registry real
    Cortex.Workers.Registry
  end
end