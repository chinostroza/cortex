# 🚀 Tutorial 1: De 0 a Multi-Provider en Elixir

*Cómo construir un gateway de IA resiliente desde cero*

---

## 🎯 **Lo que aprenderás**

Al final de este tutorial tendrás:
- Un gateway multi-provider funcionando
- 3 APIs de IA integradas (Groq, Gemini, Cohere)
- Sistema de failover automático
- Arquitectura escalable con GenServers

---

## 🏗️ **Parte 1: La Arquitectura Mental**

### **¿Por qué necesitas múltiples providers?**

```
❌ Arquitectura tradicional:
App → OpenAI API → 💥 Error 429 → App muerta

✅ Arquitectura multi-provider:  
App → Gateway → [Groq, Gemini, Cohere] → Siempre responde
```

### **El patrón que cambió todo: Worker Pool**

En lugar de llamadas directas a APIs, creamos **workers especializados**:

```elixir
# Cada provider = Un worker GenServer
GroqWorker     → API de Groq
GeminiWorker   → API de Gemini  
CohereWorker   → API de Cohere
```

**¿Por qué GenServers?**
- ✅ Aislamiento de fallos
- ✅ Estado persistente  
- ✅ Supervisión automática
- ✅ Concurrencia sin dolor

---

## 🛠️ **Parte 2: Setup del Proyecto**

### **1. Crear el proyecto Phoenix**

```bash
# Instalar Phoenix (si no lo tienes)
mix archive.install hex phx_new

# Crear proyecto
mix phx.new cortex --no-ecto --no-assets
cd cortex
```

### **2. Dependencias esenciales**

Edita `mix.exs`:

```elixir
defp deps do
  [
    # Phoenix core
    {:phoenix, "~> 1.8.0"},
    {:plug_cowboy, "~> 2.5"},
    {:jason, "~> 1.2"},
    
    # HTTP client para APIs
    {:req, "~> 0.4.0"},
    
    # Server-Sent Events
    {:plug, "~> 1.14"},
    
    # Testing
    {:ex_machina, "~> 2.7", only: [:test]}
  ]
end
```

```bash
mix deps.get
```

---

## 🧠 **Parte 3: El Behaviour Pattern**

### **3. Definir el contrato común**

Todos los workers seguirán el mismo "contrato":

```elixir
# lib/cortex/workers/worker.ex
defmodule Cortex.Workers.Worker do
  @moduledoc """
  Behaviour que define el contrato para todos los workers de IA.
  """
  
  @callback stream_completion(worker :: term(), messages :: list(), opts :: keyword()) :: 
    {:ok, Enumerable.t()} | {:error, term()}
  
  @callback health_check(worker :: term()) :: 
    {:ok, :available | :degraded} | {:error, term()}
  
  @callback priority(worker :: term()) :: integer()
  
  @callback transform_messages(messages :: list(), opts :: keyword()) :: list()
end
```

**¿Por qué un behaviour?**
- 🎯 **Consistencia**: Todos los workers funcionan igual
- 🔄 **Intercambiabilidad**: Fácil agregar nuevos providers  
- 🧪 **Testing**: Mock fácil de cualquier provider
- 📖 **Documentación**: El código se autodocumenta

---

## ⚡ **Parte 4: Tu Primer Worker - Groq**

### **4. Estructura del GroqWorker**

```elixir
# lib/cortex/workers/adapters/groq_worker.ex
defmodule Cortex.Workers.Adapters.GroqWorker do
  @moduledoc """
  Worker para Groq API - El más rápido del oeste 🤠
  """
  
  @behaviour Cortex.Workers.Worker
  
  defstruct [
    :name,
    :api_keys,        # Lista para rotación
    :current_key_index,
    :default_model,
    :timeout,
    :last_rotation
  ]
  
  @default_timeout 30_000
  @default_model "llama-3.1-8b-instant"
  @base_url "https://api.groq.com"
  
  # Constructor
  def new(opts) do
    api_keys = case Keyword.get(opts, :api_keys) do
      keys when is_list(keys) and keys != [] -> keys
      single_key when is_binary(single_key) -> [single_key]  
      _ -> raise ArgumentError, "Se necesitan API keys"
    end
    
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      api_keys: api_keys,
      current_key_index: 0,
      default_model: Keyword.get(opts, :default_model, @default_model),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      last_rotation: nil
    }
  end
end
```

### **5. Implementar el contrato**

```elixir
# Continuación de groq_worker.ex

@impl true
def priority(_worker), do: 20  # Alta prioridad

@impl true  
def transform_messages(messages, _opts) do
  # Groq usa formato OpenAI nativo
  messages
end

@impl true
def health_check(worker) do
  current_key = get_current_api_key(worker)
  headers = [{"authorization", "Bearer #{current_key}"}]
  
  case Req.get(@base_url <> "/openai/v1/models", headers: headers) do
    {:ok, %{status: 200}} -> {:ok, :available}
    {:ok, %{status: 401}} -> {:error, :invalid_key}
    {:ok, %{status: 429}} -> {:ok, :degraded}  # Rate limited pero funciona
    _ -> {:error, :unavailable}
  end
rescue
  _ -> {:error, :network_error}
end

@impl true
def stream_completion(worker, messages, opts) do
  model = Keyword.get(opts, :model, worker.default_model)
  
  payload = %{
    model: model,
    messages: transform_messages(messages, opts),
    stream: true,
    temperature: Keyword.get(opts, :temperature, 0.7),
    max_tokens: Keyword.get(opts, :max_tokens, 1000)
  }
  
  current_key = get_current_api_key(worker)
  headers = [
    {"authorization", "Bearer #{current_key}"},
    {"content-type", "application/json"}
  ]
  
  # Crear request
  url = @base_url <> "/openai/v1/chat/completions"
  
  # Stream real con Req
  case Req.post(url, headers: headers, json: payload, receive_timeout: worker.timeout) do
    {:ok, %{status: 200} = response} ->
      stream = parse_sse_stream(response.body)
      {:ok, stream}
    
    {:ok, %{status: 429}} ->
      # Rate limit - rotar key y reintentar
      rotated_worker = rotate_api_key(worker)
      stream_completion(rotated_worker, messages, opts)
    
    {:ok, %{status: status}} ->
      {:error, {:http_error, status}}
    
    {:error, reason} ->
      {:error, reason}
  end
end

# Helpers privados
defp get_current_api_key(worker) do
  Enum.at(worker.api_keys, worker.current_key_index)
end

defp rotate_api_key(worker) do
  new_index = rem(worker.current_key_index + 1, length(worker.api_keys))
  %{worker | current_key_index: new_index, last_rotation: DateTime.utc_now()}
end

defp parse_sse_stream(body) do
  body
  |> String.split("\n")
  |> Stream.filter(&String.starts_with?(&1, "data: "))
  |> Stream.map(&String.replace_prefix(&1, "data: ", ""))
  |> Stream.filter(&(&1 != "[DONE]"))
  |> Stream.map(fn chunk ->
    case Jason.decode(chunk) do
      {:ok, %{"choices" => [%{"delta" => %{"content" => content}}]}} -> content
      _ -> ""
    end
  end)
  |> Stream.filter(&(&1 != ""))
end
```

---

## 🎯 **Parte 5: El Registry Pattern**

### **6. Registry para descubrimiento de workers**

```elixir
# lib/cortex/workers/registry.ex
defmodule Cortex.Workers.Registry do
  @moduledoc """
  Registry dinámico para workers. 
  Permite registrar, descubrir y remover workers en runtime.
  """
  
  use GenServer
  
  # Client API
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end
  
  def register(registry \\ __MODULE__, name, worker) do
    GenServer.call(registry, {:register, name, worker})
  end
  
  def get_worker(registry \\ __MODULE__, name) do
    GenServer.call(registry, {:get_worker, name})
  end
  
  def list_all(registry \\ __MODULE__) do
    GenServer.call(registry, :list_all)
  end
  
  def unregister(registry \\ __MODULE__, name) do
    GenServer.call(registry, {:unregister, name})
  end
  
  # Server callbacks
  @impl true
  def init(_) do
    {:ok, %{}}
  end
  
  @impl true
  def handle_call({:register, name, worker}, _from, workers) do
    case Map.has_key?(workers, name) do
      true -> {:reply, {:error, :already_registered}, workers}
      false -> {:reply, :ok, Map.put(workers, name, worker)}
    end
  end
  
  @impl true
  def handle_call({:get_worker, name}, _from, workers) do
    result = case Map.fetch(workers, name) do
      {:ok, worker} -> {:ok, worker}
      :error -> {:error, :not_found}
    end
    {:reply, result, workers}
  end
  
  @impl true  
  def handle_call(:list_all, _from, workers) do
    worker_list = workers |> Map.values()
    {:reply, worker_list, workers}
  end
  
  @impl true
  def handle_call({:unregister, name}, _from, workers) do
    {:reply, :ok, Map.delete(workers, name)}
  end
end
```

---

## 🎱 **Parte 6: El Pool Inteligente**

### **7. Pool con estrategia de failover**

```elixir  
# lib/cortex/workers/pool.ex
defmodule Cortex.Workers.Pool do
  @moduledoc """
  Pool inteligente que selecciona el mejor worker según prioridad.
  Maneja failover automático cuando un worker falla.
  """
  
  use GenServer
  require Logger
  
  defstruct [:registry, :strategy, :health_status]
  
  # Client API
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  def stream_completion(pool \\ __MODULE__, messages, opts \\ []) do
    GenServer.call(pool, {:stream_completion, messages, opts}, 30_000)
  end
  
  def health_status(pool \\ __MODULE__) do
    GenServer.call(pool, :health_status)
  end
  
  # Server callbacks
  @impl true
  def init(opts) do
    registry = Keyword.get(opts, :registry, Cortex.Workers.Registry)
    strategy = Keyword.get(opts, :strategy, :priority_first)
    
    state = %__MODULE__{
      registry: registry,
      strategy: strategy, 
      health_status: %{}
    }
    
    # Health check periódico
    Process.send_after(self(), :health_check, 1000)
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:stream_completion, messages, opts}, _from, state) do
    case select_best_worker(state) do
      {:ok, worker} ->
        result = try_with_failover([worker], messages, opts, state)
        {:reply, result, state}
      
      {:error, :no_workers} ->
        {:reply, {:error, :no_workers_available}, state}
    end
  end
  
  @impl true
  def handle_call(:health_status, _from, state) do
    {:reply, state.health_status, state}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    new_health_status = perform_health_checks(state.registry)
    
    # Siguiente check en 30 segundos
    Process.send_after(self(), :health_check, 30_000)
    
    {:noreply, %{state | health_status: new_health_status}}
  end
  
  # Private functions
  defp select_best_worker(state) do
    workers = Registry.list_all(state.registry)
    
    available_workers = workers
    |> Enum.filter(fn worker ->
      health = Map.get(state.health_status, worker.name, :unknown)
      health == :available
    end)
    |> Enum.sort_by(fn worker ->
      apply(worker.__struct__, :priority, [worker])
    end)
    
    case available_workers do
      [best_worker | _] -> {:ok, best_worker}
      [] -> {:error, :no_workers}
    end
  end
  
  defp try_with_failover([], _messages, _opts, _state) do
    {:error, :all_workers_failed}
  end
  
  defp try_with_failover([worker | rest], messages, opts, state) do
    Logger.info("Intentando con worker: #{worker.name}")
    
    case apply(worker.__struct__, :stream_completion, [worker, messages, opts]) do
      {:ok, stream} -> 
        {:ok, stream}
      
      {:error, reason} ->
        Logger.warning("Worker #{worker.name} falló: #{inspect(reason)}")
        try_with_failover(rest, messages, opts, state)
    end
  end
  
  defp perform_health_checks(registry) do
    workers = Registry.list_all(registry)
    
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
    
    # Recolectar resultados
    tasks
    |> Task.yield_many(5000)
    |> Enum.map(fn {_task, result} ->
      case result do
        {:ok, value} -> value
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end
end
```

---

## 🎮 **Parte 7: Integrando Todo**

### **8. Supervisor principal**

```elixir
# lib/cortex/workers/supervisor.ex
defmodule Cortex.Workers.Supervisor do
  @moduledoc """
  Supervisor que maneja Registry, Pool y Workers.
  """
  
  use Supervisor
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    children = [
      # Registry debe ir primero
      {Cortex.Workers.Registry, []},
      
      # Pool depende del Registry  
      {Cortex.Workers.Pool, [registry: Cortex.Workers.Registry]},
      
      # Task para registrar workers iniciales
      {Task, fn -> configure_initial_workers() end}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  defp configure_initial_workers do
    # Registrar Groq worker
    groq_keys = get_env_list("GROQ_API_KEYS")
    
    if not Enum.empty?(groq_keys) do
      worker = Cortex.Workers.Adapters.GroqWorker.new([
        name: "groq-primary",
        api_keys: groq_keys,
        default_model: System.get_env("GROQ_MODEL", "llama-3.1-8b-instant")
      ])
      
      Cortex.Workers.Registry.register("groq-primary", worker)
      IO.puts("✅ Groq worker registrado")
    end
  end
  
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
end
```

### **9. Agregar al Application**

```elixir
# lib/cortex/application.ex
def start(_type, _args) do
  children = [
    CortexWeb.Telemetry,
    {Phoenix.PubSub, name: Cortex.PubSub},
    
    # 🎯 Agregar nuestro supervisor
    Cortex.Workers.Supervisor,
    
    CortexWeb.Endpoint
  ]
  
  opts = [strategy: :one_for_one, name: Cortex.Supervisor]
  Supervisor.start_link(children, opts)
end
```

---

## 🚀 **Parte 8: Primera Prueba**

### **10. Crear un dispatcher simple**

```elixir
# lib/cortex/dispatcher.ex
defmodule Cortex.Dispatcher do
  @moduledoc """
  API pública para el sistema multi-provider.
  """
  
  def dispatch_stream(messages, opts \\ []) do
    case Cortex.Workers.Pool.stream_completion(messages, opts) do
      {:ok, stream} -> {:ok, stream}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def health_status do
    Cortex.Workers.Pool.health_status()
  end
end
```

### **11. Test básico**

```elixir
# test/cortex/workers/groq_worker_test.exs
defmodule Cortex.Workers.Adapters.GroqWorkerTest do
  use ExUnit.Case
  
  alias Cortex.Workers.Adapters.GroqWorker
  
  describe "new/1" do
    test "crea worker con configuración válida" do
      worker = GroqWorker.new([
        name: "test-groq",
        api_keys: ["test_key_123"]
      ])
      
      assert worker.name == "test-groq"
      assert worker.api_keys == ["test_key_123"]
      assert worker.current_key_index == 0
    end
    
    test "falla sin API keys" do
      assert_raise ArgumentError, fn ->
        GroqWorker.new([name: "test"])
      end
    end
  end
  
  describe "priority/1" do
    test "retorna prioridad correcta" do
      worker = GroqWorker.new([name: "test", api_keys: ["key"]])
      assert GroqWorker.priority(worker) == 20
    end
  end
end
```

### **12. Probarlo en vivo**

```bash
# Configurar environment
export GROQ_API_KEYS=tu_api_key_aquí

# Iniciar servidor
iex -S mix

# En IEx:
messages = [%{"role" => "user", "content" => "¡Hola!"}]
{:ok, stream} = Cortex.Dispatcher.dispatch_stream(messages)

# Ver el stream
stream |> Enum.take(10) |> IO.inspect()
```

---

## 🎉 **¡Felicitaciones!**

Has construido tu primer worker multi-provider. Ahora tienes:

✅ **Worker Pattern** con behaviour  
✅ **Registry dinámico** para descubrimiento  
✅ **Pool inteligente** con failover  
✅ **Health checks** automáticos  
✅ **API key rotation** 

### **🔥 Próximos pasos:**

En el siguiente tutorial agregaremos:
- Más providers (Gemini, Cohere)
- Phoenix endpoints para HTTP  
- Streaming real-time
- Manejo de errores avanzado

### **📚 Código completo:**
El código de este tutorial está en: `github.com/tuuser/cortex/tree/tutorial-1`

---

## 💡 **Conceptos clave aprendidos:**

1. **Behaviours**: Contratos que garantizan consistencia
2. **GenServer**: Estado persistente y concurrencia  
3. **Registry Pattern**: Descubrimiento dinámico de servicios
4. **Pool Pattern**: Selección inteligente de recursos
5. **Supervision**: Tolerancia a fallos automática

¿Preguntas? ¿Dudas? ¿Algo no funcionó?

**¡Nos vemos en el Tutorial 2: Phoenix + Streaming!** ⚡