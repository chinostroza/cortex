# 🏠 Tutorial 3: Ollama como backup infinito local

*Tu as en la manga cuando todas las APIs te fallan*

---

## 🎯 **Lo que aprenderás**

En este tutorial integraremos Ollama como el backup definitivo:
- Instalación y configuración de Ollama 
- Integración con el sistema multi-provider
- Estrategias de priorización inteligente
- Optimización de modelos locales
- Manejo híbrido: Cloud + Local

---

## 🧠 **Parte 1: ¿Por qué Ollama es tu seguro de vida?**

### **El escenario de pesadilla:**

```
❌ Solo APIs cloud:
- Groq: Rate limited 429 💥
- Gemini: Quota exceeded 💸  
- Cohere: Service unavailable 503 💀
- Tu app: MUERTA ☠️

✅ Con Ollama backup:
- Groq: Rate limited 429
- Gemini: Quota exceeded 💸
- Cohere: Service unavailable 503  
- Ollama: ¡Siempre disponible! 🚀
- Tu app: VIVA y respondiendo ✅
```

### **Ventajas de Ollama:**

- 🔄 **Ilimitado**: Sin rate limits ni quotas
- 🔒 **Privado**: Datos nunca salen de tu máquina  
- ⚡ **Rápido**: Especialmente con GPU
- 💰 **Gratis**: Después de la inversión inicial
- 🌐 **Offline**: Funciona sin internet

### **Desventajas (y cómo mitigarlas):**

- 🖥️ **Hardware intensivo** → Usa modelos pequeños optimizados
- 🧠 **Modelos más simples** → Ideal para tareas específicas  
- ⏱️ **Setup inicial** → Lo hacemos fácil en este tutorial

---

## 🛠️ **Parte 2: Setup de Ollama**

### **1. Instalación de Ollama**

```bash
# macOS/Linux
curl -fsSL https://ollama.ai/install.sh | sh

# Windows
# Descargar desde: https://ollama.ai/download

# Verificar instalación
ollama --version
```

### **2. Descargar modelos optimizados**

```bash
# Modelo ultra-ligero (1.5GB) - Para pruebas rápidas
ollama pull gemma2:2b

# Modelo balanceado (2.6GB) - Recomendado para producción  
ollama pull gemma2:4b

# Modelo potente (4.7GB) - Si tienes RAM suficiente
ollama pull llama3.1:8b

# Modelo código (4.1GB) - Especializado en programming
ollama pull codegemma:7b
```

### **3. Probar que funciona**

```bash
# Test básico
ollama run gemma2:2b "¡Hola! ¿Funcionas correctamente?"

# Verificar API HTTP
curl http://localhost:11434/api/generate -d '{
  "model": "gemma2:2b",
  "prompt": "Di solo: Sistema funcionando",
  "stream": false
}'
```

---

## 🏗️ **Parte 3: Ollama Worker Implementation**

### **4. Estructura del OllamaWorker**

```elixir
# lib/cortex/workers/adapters/ollama_worker.ex
defmodule Cortex.Workers.Adapters.OllamaWorker do
  @moduledoc """
  Worker para Ollama local - Tu backup infinito 🏠
  
  Características:
  - Sin rate limits ni quotas
  - Modelos optimizados para velocidad  
  - Fallback cuando APIs cloud fallan
  - Soporte para streaming
  """
  
  @behaviour Cortex.Workers.Worker
  
  defstruct [
    :name,
    :base_url,
    :models,         # Lista de modelos disponibles
    :default_model,
    :timeout,
    :concurrent_requests,  # Límite interno
    :gpu_enabled
  ]
  
  @default_timeout 60_000  # Ollama puede ser más lento
  @default_base_url "http://localhost:11434"
  @default_model "gemma2:2b"
  
  def new(opts) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    
    # Detectar modelos disponibles automáticamente
    available_models = detect_available_models(base_url) ||
                      Keyword.get(opts, :models, [@default_model])
    
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      base_url: base_url,
      models: available_models,
      default_model: List.first(available_models) || @default_model,
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      concurrent_requests: Keyword.get(opts, :concurrent_requests, 4),
      gpu_enabled: detect_gpu_support(base_url)
    }
  end
  
  @impl true
  def priority(_worker), do: 50  # Baja prioridad - usar como fallback
  
  @impl true
  def transform_messages(messages, opts) do
    # Ollama prefiere formato simple para algunos modelos
    model = opts[:model] || @default_model
    
    case String.contains?(model, ["gemma", "llama"]) do
      true -> 
        # Formato conversacional simple
        messages
        |> Enum.map(fn
          %{"role" => "user", "content" => content} -> 
            %{"role" => "user", "content" => content}
          %{"role" => "assistant", "content" => content} -> 
            %{"role" => "assistant", "content" => content}
          %{"role" => "system", "content" => content} -> 
            %{"role" => "system", "content" => content}
        end)
        
      false ->
        # Modelo soporta formato complejo
        messages
    end
  end
  
  @impl true
  def health_check(worker) do
    case Req.get(worker.base_url <> "/api/tags", receive_timeout: 3000) do
      {:ok, %{status: 200, body: body}} ->
        models = parse_available_models(body)
        
        if length(models) > 0 do
          {:ok, :available}
        else
          {:error, :no_models}
        end
        
      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}
        
      {:error, %{reason: :econnrefused}} ->
        {:error, :ollama_not_running}
        
      {:error, reason} ->
        {:error, reason}
    end
  rescue
    _ -> {:error, :health_check_failed}
  end
  
  @impl true
  def stream_completion(worker, messages, opts) do
    model = select_best_model(worker, opts)
    transformed_messages = transform_messages(messages, opts)
    
    # Construir prompt para modelos que no soportan messages
    prompt = case supports_messages?(model) do
      true -> nil  # Usar messages format
      false -> build_prompt_from_messages(transformed_messages)
    end
    
    payload = %{
      model: model,
      stream: true,
      options: build_ollama_options(opts)
    }
    |> maybe_add_messages(transformed_messages, prompt)
    
    url = worker.base_url <> "/api/chat"
    
    case make_streaming_request(url, payload, worker.timeout) do
      {:ok, stream} -> {:ok, stream}
      {:error, reason} -> {:error, reason}
    end
  end
  
  # --- PRIVATE FUNCTIONS ---
  
  defp detect_available_models(base_url) do
    case Req.get(base_url <> "/api/tags", receive_timeout: 5000) do
      {:ok, %{status: 200, body: body}} -> 
        parse_available_models(body)
      _ -> 
        nil
    end
  rescue
    _ -> nil
  end
  
  defp parse_available_models(body) when is_map(body) do
    body
    |> Map.get("models", [])
    |> Enum.map(fn model -> model["name"] end)
    |> Enum.filter(&is_binary/1)
  end
  
  defp parse_available_models(_), do: []
  
  defp detect_gpu_support(base_url) do
    # Hacer request simple para detectar si hay GPU
    payload = %{
      model: "gemma2:2b",
      prompt: "test",
      stream: false,
      options: %{num_predict: 1}
    }
    
    start_time = System.monotonic_time(:millisecond)
    
    case Req.post(base_url <> "/api/generate", json: payload, receive_timeout: 10_000) do
      {:ok, %{status: 200}} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time
        
        # Si responde muy rápido, probablemente tiene GPU
        duration < 1000
        
      _ -> 
        false
    end
  rescue
    _ -> false
  end
  
  defp select_best_model(worker, opts) do
    requested_model = opts[:model]
    
    cond do
      # Si se solicita un modelo específico y está disponible
      requested_model && requested_model in worker.models ->
        requested_model
        
      # Si el modelo solicitado no está, buscar similar
      requested_model ->
        find_similar_model(worker.models, requested_model) || worker.default_model
        
      # Usar modelo por defecto
      true ->
        worker.default_model
    end
  end
  
  defp find_similar_model(available_models, requested_model) do
    requested_lower = String.downcase(requested_model)
    
    # Buscar por nombre base (ej: "llama" en "llama3.1:8b")
    Enum.find(available_models, fn model ->
      model_lower = String.downcase(model)
      String.contains?(requested_lower, String.split(model_lower, ":") |> hd())
    end)
  end
  
  defp supports_messages?(model) do
    # Modelos que soportan format de messages
    String.contains?(model, ["llama3", "gemma2", "qwen", "phi3"])
  end
  
  defp build_prompt_from_messages(messages) do
    messages
    |> Enum.map(fn
      %{"role" => "system", "content" => content} ->
        "System: #{content}"
        
      %{"role" => "user", "content" => content} ->
        "User: #{content}"
        
      %{"role" => "assistant", "content" => content} ->
        "Assistant: #{content}"
    end)
    |> Enum.join("\n\n")
    |> Kernel.<>("\n\nAssistant:")
  end
  
  defp build_ollama_options(opts) do
    %{}
    |> maybe_add_option(:temperature, opts[:temperature])
    |> maybe_add_option(:num_predict, opts[:max_tokens])
    |> maybe_add_option(:top_p, opts[:top_p])
    |> maybe_add_option(:repeat_penalty, opts[:frequency_penalty])
  end
  
  defp maybe_add_option(options, _key, nil), do: options
  defp maybe_add_option(options, key, value), do: Map.put(options, key, value)
  
  defp maybe_add_messages(payload, messages, nil) do
    Map.put(payload, :messages, messages)
  end
  
  defp maybe_add_messages(payload, _messages, prompt) do
    payload
    |> Map.delete(:messages)
    |> Map.put(:prompt, prompt)
  end
  
  defp make_streaming_request(url, payload, timeout) do
    case Req.post(url, json: payload, receive_timeout: timeout, into: :self) do
      {:ok, response} ->
        stream = parse_ollama_stream(response.body)
        {:ok, stream}
        
      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, error}
  end
  
  defp parse_ollama_stream(body) when is_binary(body) do
    body
    |> String.split("\n")
    |> Stream.filter(&(String.trim(&1) != ""))
    |> Stream.map(&parse_ollama_chunk/1)
    |> Stream.filter(&(&1 != nil))
  end
  
  defp parse_ollama_stream(stream) do
    # Para streams que vienen como Enumerable
    stream
    |> Stream.map(&parse_ollama_chunk/1)
    |> Stream.filter(&(&1 != nil))
  end
  
  defp parse_ollama_chunk(chunk) when is_binary(chunk) do
    case Jason.decode(chunk) do
      {:ok, %{"message" => %{"content" => content}}} when is_binary(content) ->
        content
        
      {:ok, %{"response" => content}} when is_binary(content) ->
        content
        
      {:ok, %{"done" => true}} ->
        nil  # Fin del stream
        
      _ ->
        nil
    end
  rescue
    _ -> nil
  end
  
  defp parse_ollama_chunk(_), do: nil
end
```

---

## 🎯 **Parte 4: Estrategias de Priorización**

### **5. Pool Strategy modificado**

```elixir
# lib/cortex/workers/pool.ex - actualizar select_best_worker

defp select_best_worker(state, opts \\ []) do
  workers = Registry.list_all(state.registry)
  
  # Filtrar workers disponibles
  available_workers = workers
  |> filter_healthy_workers(state.health_status)
  |> apply_selection_strategy(state.strategy, opts)
  
  case available_workers do
    [best_worker | fallbacks] -> {:ok, best_worker, fallbacks}
    [] -> {:error, :no_workers}
  end
end

defp filter_healthy_workers(workers, health_status) do
  workers
  |> Enum.filter(fn worker ->
    health = Map.get(health_status, worker.name, :unknown)
    health in [:available, :degraded]  # Incluir degraded como último recurso
  end)
end

defp apply_selection_strategy(workers, strategy, opts) do
  case strategy do
    :cloud_first -> 
      sort_cloud_first(workers)
    
    :local_first ->
      sort_local_first(workers)  
      
    :speed_first ->
      sort_by_speed(workers, opts)
      
    :cost_first ->
      sort_by_cost(workers)
      
    _ -> 
      # Default: prioridad híbrida inteligente
      sort_hybrid_priority(workers)
  end
end

defp sort_cloud_first(workers) do
  workers
  |> Enum.sort_by(fn worker ->
    case get_worker_type(worker) do
      "ollama" -> {2, apply(worker.__struct__, :priority, [worker])}  # Último
      _ -> {1, apply(worker.__struct__, :priority, [worker])}         # Primero
    end
  end)
end

defp sort_local_first(workers) do
  workers  
  |> Enum.sort_by(fn worker ->
    case get_worker_type(worker) do
      "ollama" -> {1, apply(worker.__struct__, :priority, [worker])}  # Primero
      _ -> {2, apply(worker.__struct__, :priority, [worker])}         # Último
    end
  end)
end

defp sort_hybrid_priority(workers) do
  # Estrategia por defecto: Cloud rápido → Cloud inteligente → Local backup
  workers
  |> Enum.sort_by(fn worker ->
    case get_worker_type(worker) do
      "groq" -> 10     # Ultra-rápido primero
      "gemini" -> 20   # Inteligente segundo  
      "cohere" -> 30   # Conversacional tercero
      "ollama" -> 40   # Backup local último
      _ -> 50
    end
  end)
end

defp get_worker_type(worker) do
  case worker.__struct__ do
    Cortex.Workers.Adapters.OllamaWorker -> "ollama"
    Cortex.Workers.Adapters.GroqWorker -> "groq"
    Cortex.Workers.Adapters.GeminiWorker -> "gemini"
    Cortex.Workers.Adapters.CohereWorker -> "cohere"
    _ -> "unknown"
  end
end
```

---

## ⚡ **Parte 5: Optimización de Performance**

### **6. Lazy Loading de modelos**

```elixir
# lib/cortex/workers/adapters/ollama_model_manager.ex
defmodule Cortex.Workers.Adapters.OllamaModelManager do
  @moduledoc """
  Maneja la carga inteligente de modelos Ollama.
  Los modelos se cargan solo cuando se necesitan.
  """
  
  use GenServer
  require Logger
  
  defstruct [:base_url, :loaded_models, :model_sizes, :max_memory_mb]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def ensure_model_loaded(model_name) do
    GenServer.call(__MODULE__, {:ensure_loaded, model_name}, 30_000)
  end
  
  def get_loaded_models do
    GenServer.call(__MODULE__, :get_loaded)
  end
  
  def unload_unused_models do
    GenServer.cast(__MODULE__, :cleanup)
  end
  
  @impl true
  def init(opts) do
    base_url = Keyword.get(opts, :base_url, "http://localhost:11434")
    max_memory_mb = Keyword.get(opts, :max_memory_mb, 8192)  # 8GB default
    
    state = %__MODULE__{
      base_url: base_url,
      loaded_models: MapSet.new(),
      model_sizes: %{},
      max_memory_mb: max_memory_mb
    }
    
    # Detectar modelos disponibles al inicio
    {:ok, detect_installed_models(state)}
  end
  
  @impl true
  def handle_call({:ensure_loaded, model_name}, _from, state) do
    if MapSet.member?(state.loaded_models, model_name) do
      {:reply, :ok, state}
    else
      case load_model(model_name, state) do
        {:ok, new_state} ->
          Logger.info("Modelo #{model_name} cargado exitosamente")
          {:reply, :ok, new_state}
          
        {:error, reason} ->
          Logger.error("Error cargando modelo #{model_name}: #{inspect(reason)}")
          {:reply, {:error, reason}, state}
      end
    end
  end
  
  @impl true  
  def handle_call(:get_loaded, _from, state) do
    {:reply, MapSet.to_list(state.loaded_models), state}
  end
  
  @impl true
  def handle_cast(:cleanup, state) do
    # Lógica de limpieza: descargar modelos no usados recientemente
    {:noreply, cleanup_unused_models(state)}
  end
  
  defp detect_installed_models(state) do
    case Req.get(state.base_url <> "/api/tags") do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        model_info = Enum.reduce(models, %{}, fn model, acc ->
          name = model["name"]
          size_mb = (model["size"] || 0) / (1024 * 1024)
          Map.put(acc, name, round(size_mb))
        end)
        
        %{state | model_sizes: model_info}
        
      _ ->
        Logger.warning("No se pudieron detectar modelos instalados")
        state
    end
  end
  
  defp load_model(model_name, state) do
    # Verificar si hay suficiente memoria
    case check_memory_availability(model_name, state) do
      {:ok, freed_state} ->
        # Hacer request para cargar el modelo
        case warm_up_model(model_name, freed_state.base_url) do
          :ok ->
            new_loaded = MapSet.put(freed_state.loaded_models, model_name)
            {:ok, %{freed_state | loaded_models: new_loaded}}
            
          {:error, reason} ->
            {:error, reason}
        end
        
      {:error, :insufficient_memory} ->
        {:error, :insufficient_memory}
    end
  end
  
  defp check_memory_availability(model_name, state) do
    model_size = Map.get(state.model_sizes, model_name, 2000)  # Default 2GB
    
    current_memory = calculate_current_memory_usage(state)
    available_memory = state.max_memory_mb - current_memory
    
    if available_memory >= model_size do
      {:ok, state}
    else
      # Intentar liberar memoria descargando modelos
      case free_memory_for_model(model_size, state) do
        {:ok, freed_state} -> {:ok, freed_state}
        :error -> {:error, :insufficient_memory}
      end
    end
  end
  
  defp calculate_current_memory_usage(state) do
    state.loaded_models
    |> Enum.reduce(0, fn model_name, acc ->
      size = Map.get(state.model_sizes, model_name, 0)
      acc + size
    end)
  end
  
  defp free_memory_for_model(needed_mb, state) do
    # Estrategia simple: descargar el modelo más grande que no sea crítico
    candidates = state.loaded_models
    |> MapSet.to_list()
    |> Enum.reject(&is_critical_model?/1)  # Mantener modelos críticos
    |> Enum.sort_by(&Map.get(state.model_sizes, &1, 0), :desc)
    
    case find_models_to_unload(candidates, needed_mb, state.model_sizes, 0, []) do
      {:ok, to_unload} ->
        new_loaded = Enum.reduce(to_unload, state.loaded_models, fn model, acc ->
          MapSet.delete(acc, model)
        end)
        
        {:ok, %{state | loaded_models: new_loaded}}
        
      :error ->
        :error
    end
  end
  
  defp find_models_to_unload([], _needed, _sizes, _freed, _unloaded), do: :error
  
  defp find_models_to_unload([model | rest], needed, sizes, freed_so_far, unloaded) do
    model_size = Map.get(sizes, model, 0)
    new_freed = freed_so_far + model_size
    new_unloaded = [model | unloaded]
    
    if new_freed >= needed do
      {:ok, new_unloaded}
    else
      find_models_to_unload(rest, needed, sizes, new_freed, new_unloaded)
    end
  end
  
  defp is_critical_model?(model_name) do
    # Mantener modelos pequeños y rápidos siempre cargados
    String.contains?(model_name, ["2b", "gemma2:2b"])
  end
  
  defp warm_up_model(model_name, base_url) do
    # Hacer una inferencia pequeña para cargar el modelo en memoria
    payload = %{
      model: model_name,
      prompt: "Test",
      stream: false,
      options: %{num_predict: 1}
    }
    
    case Req.post(base_url <> "/api/generate", json: payload, receive_timeout: 30_000) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp cleanup_unused_models(state) do
    # Por ahora, implementación simple
    # En producción: tracking de uso, LRU cache, etc.
    state
  end
end
```

---

## 🔧 **Parte 6: Configuración Avanzada**

### **7. Variables de entorno para Ollama**

```elixir
# config/runtime.exs - agregar configuración Ollama

if config_env() == :prod do
  # Configuración Ollama para producción
  ollama_config = [
    base_url: System.get_env("OLLAMA_BASE_URL") || "http://localhost:11434",
    models: parse_model_list(System.get_env("OLLAMA_MODELS") || "gemma2:2b,llama3.1:8b"),
    max_memory_mb: String.to_integer(System.get_env("OLLAMA_MAX_MEMORY_MB") || "8192"),
    concurrent_requests: String.to_integer(System.get_env("OLLAMA_MAX_CONCURRENT") || "4"),
    gpu_enabled: System.get_env("OLLAMA_GPU_ENABLED") == "true",
    auto_pull_models: System.get_env("OLLAMA_AUTO_PULL") == "true"
  ]
  
  config :cortex, :ollama, ollama_config
end

defp parse_model_list(models_string) do
  models_string
  |> String.split(",")
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))
end
```

### **8. Dockerfile optimizado para Ollama**

```dockerfile
# Dockerfile.with-ollama
FROM elixir:1.15-alpine AS build

# Install build dependencies
RUN apk add --no-cache build-base git curl

# Set build ENV
ENV MIX_ENV=prod

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Create app directory and copy the Elixir projects into it
WORKDIR /app
COPY mix.exs mix.lock ./
COPY config config
COPY lib lib
COPY priv priv

# Install mix dependencies
RUN mix deps.get --only prod
RUN mix deps.compile

# Compile the release
RUN mix compile

# Build the release
RUN mix release

# Start a new build stage for Ollama + Runtime
FROM python:3.11-slim

# Install Ollama
RUN curl -fsSL https://ollama.ai/install.sh | sh

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create app user
RUN useradd --create-home app
WORKDIR /home/app
USER app

# Copy the release from build stage
COPY --from=build --chown=app:app /app/_build/prod/rel/cortex ./cortex

# Copy entrypoint script
COPY --chown=app:app docker/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

# Environment variables
ENV MIX_ENV=prod
ENV OLLAMA_BASE_URL=http://localhost:11434
ENV OLLAMA_MODELS=gemma2:2b,llama3.1:8b
ENV OLLAMA_MAX_MEMORY_MB=8192

# Expose ports
EXPOSE 4000 11434

# Start both Ollama and Cortex
ENTRYPOINT ["./entrypoint.sh"]
```

```bash
#!/bin/bash
# docker/entrypoint.sh

echo "🚀 Starting Cortex with Ollama..."

# Start Ollama in background
ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to be ready
echo "⏳ Waiting for Ollama to start..."
while ! curl -s http://localhost:11434/api/tags > /dev/null; do
  sleep 2
done

# Pull required models
echo "📦 Pulling models..."
IFS=',' read -ra MODELS <<< "$OLLAMA_MODELS"
for model in "${MODELS[@]}"; do
    echo "Pulling $model..."
    ollama pull "$model"
done

echo "✅ Ollama ready with models: $OLLAMA_MODELS"

# Start Cortex
echo "🌐 Starting Cortex server..."
exec ./cortex/bin/cortex start
```

---

## 🧪 **Parte 7: Testing Híbrido**

### **9. Test de fallback Cloud → Local**

```elixir
# test/cortex/workers/ollama_fallback_test.exs
defmodule Cortex.Workers.OllamaFallbackTest do
  use ExUnit.Case
  
  alias Cortex.Workers.{Registry, Pool}
  alias Cortex.Workers.Adapters.{MockFailingWorker, OllamaWorker}
  
  setup do
    # Crear workers mock que fallan
    failing_groq = MockFailingWorker.new([
      name: "failing-groq",
      error: {:error, :rate_limited}
    ])
    
    failing_gemini = MockFailingWorker.new([
      name: "failing-gemini", 
      error: {:error, :quota_exceeded}
    ])
    
    # Worker Ollama real (requiere Ollama corriendo)
    ollama_worker = OllamaWorker.new([
      name: "ollama-backup",
      base_url: "http://localhost:11434",
      models: ["gemma2:2b"]
    ])
    
    # Registrar workers
    Registry.register("failing-groq", failing_groq)
    Registry.register("failing-gemini", failing_gemini)  
    Registry.register("ollama-backup", ollama_worker)
    
    on_exit(fn ->
      Registry.unregister("failing-groq")
      Registry.unregister("failing-gemini")
      Registry.unregister("ollama-backup")
    end)
    
    :ok
  end
  
  @tag :integration
  test "fallback de cloud APIs a Ollama cuando fallan" do
    messages = [%{"role" => "user", "content" => "Di solo: Test exitoso"}]
    
    # Simular que las APIs cloud fallan
    {:ok, stream} = Pool.stream_completion(messages)
    
    # El stream debería venir de Ollama
    response = stream
    |> Enum.take(10)
    |> Enum.join("")
    
    assert String.contains?(response, ["Test", "exitoso"]) || 
           String.length(response) > 0,
           "Ollama debería responder cuando las APIs cloud fallan"
  end
  
  @tag :integration  
  test "Ollama responde con modelo específico" do
    messages = [%{"role" => "user", "content" => "¿Qué modelo eres?"}]
    
    {:ok, stream} = Pool.stream_completion(messages, model: "gemma2:2b")
    
    response = stream |> Enum.take(20) |> Enum.join("")
    
    assert String.length(response) > 0
  end
end
```

### **10. Benchmark Cloud vs Local**

```elixir
# test/benchmarks/cloud_vs_local_benchmark.exs
defmodule CloudVsLocalBenchmark do
  use ExUnit.Case
  
  @tag :benchmark
  test "comparar velocidad cloud vs local" do
    messages = [%{"role" => "user", "content" => "Cuenta del 1 al 5"}]
    
    # Benchmark Groq (cloud)
    groq_time = :timer.tc(fn ->
      case test_provider("groq", messages) do
        {:ok, _} -> :ok
        _ -> :error
      end
    end)
    
    # Benchmark Ollama (local)  
    ollama_time = :timer.tc(fn ->
      case test_provider("ollama", messages) do
        {:ok, _} -> :ok
        _ -> :error
      end
    end)
    
    IO.puts("\n🏃‍♂️ Benchmark Results:")
    IO.puts("Groq (cloud):  #{elem(groq_time, 0) / 1000}ms")
    IO.puts("Ollama (local): #{elem(ollama_time, 0) / 1000}ms")
    
    # Ambos deberían responder
    assert elem(groq_time, 1) == :ok || elem(ollama_time, 1) == :ok
  end
  
  defp test_provider(type, messages) do
    case Cortex.Dispatcher.dispatch_stream(messages, provider: type) do
      {:ok, stream} -> 
        response = stream |> Enum.take(5) |> Enum.join("")
        if String.length(response) > 0, do: {:ok, response}, else: {:error, :empty}
      error -> 
        error
    end
  rescue
    _ -> {:error, :exception}
  end
end
```

---

## 🚀 **Parte 8: Deployment con Ollama**

### **11. Docker Compose para desarrollo**

```yaml
# docker-compose.yml
version: '3.8'

services:
  ollama:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    environment:
      - OLLAMA_ORIGINS=http://localhost:4000
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3
      
  cortex:
    build: 
      context: .
      dockerfile: Dockerfile
    ports:
      - "4000:4000"
    environment:
      - MIX_ENV=prod
      - GROQ_API_KEYS=${GROQ_API_KEYS}
      - GEMINI_API_KEYS=${GEMINI_API_KEYS}
      - COHERE_API_KEYS=${COHERE_API_KEYS}
      - OLLAMA_BASE_URL=http://ollama:11434
      - OLLAMA_MODELS=gemma2:2b,llama3.1:8b
    depends_on:
      ollama:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  ollama_data:
```

### **12. Script de inicialización**

```bash
#!/bin/bash
# scripts/setup-ollama.sh

echo "🏠 Configurando Ollama para Cortex..."

# Verificar si Ollama está instalado
if ! command -v ollama &> /dev/null; then
    echo "📦 Instalando Ollama..."
    curl -fsSL https://ollama.ai/install.sh | sh
fi

# Iniciar Ollama si no está corriendo
if ! curl -s http://localhost:11434/api/tags > /dev/null; then
    echo "🚀 Iniciando Ollama..."
    ollama serve &
    OLLAMA_PID=$!
    
    # Esperar a que inicie
    while ! curl -s http://localhost:11434/api/tags > /dev/null; do
        echo "⏳ Esperando Ollama..."
        sleep 2
    done
fi

# Descargar modelos recomendados
echo "📥 Descargando modelos optimizados..."

# Modelo ultra-ligero para pruebas rápidas
ollama pull gemma2:2b

# Modelo balanceado para producción  
ollama pull llama3.1:8b

# Modelo especializado en código (opcional)
read -p "¿Descargar modelo de código? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ollama pull codegemma:7b
fi

echo "✅ Ollama configurado y listo!"
echo ""
echo "🔧 Configuración recomendada:"
echo "export OLLAMA_BASE_URL=http://localhost:11434"
echo "export OLLAMA_MODELS=gemma2:2b,llama3.1:8b"
echo "export OLLAMA_MAX_MEMORY_MB=8192"
echo ""
echo "🧪 Prueba rápida:"
echo "ollama run gemma2:2b \"¡Hola! ¿Funcionas correctamente?\""
```

---

## 🎉 **¡Felicitaciones!**

Has integrado Ollama como backup infinito. Ahora tienes:

✅ **Backup local ilimitado** cuando APIs cloud fallan  
✅ **Gestión inteligente de modelos** con lazy loading  
✅ **Estrategias híbridas** Cloud + Local  
✅ **Performance optimizado** para hardware local  
✅ **Docker support** para deployment fácil  

### **🎯 Arquitectura final:**

```
Request → Pool Strategy:
  1. Groq (ultra-rápido, rate limited) 
  2. Gemini (inteligente, quotas)
  3. Cohere (conversacional, limitado)  
  4. Ollama (local, INFINITO) ← Nunca falla
```

### **📊 Beneficios obtenidos:**

- **99.9% uptime**: Siempre hay un provider disponible
- **Cost optimization**: Solo usa APIs pagadas cuando vale la pena  
- **Privacy option**: Datos sensibles pueden ir solo a Ollama
- **Offline capability**: Sistema funciona sin internet

### **🔧 Para usar:**

```bash
# Setup automático
./scripts/setup-ollama.sh

# Con Docker
docker-compose up -d

# Testing
curl -N -X POST localhost:4000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"¡Hola desde el backup infinito!"}]}'
```

---

## 💡 **Conceptos clave aprendidos:**

1. **Local-first strategy**: Backup que nunca falla
2. **Model management**: Lazy loading optimizado  
3. **Hybrid architecture**: Best of both worlds
4. **Resource optimization**: Gestión inteligente de memoria
5. **Deployment strategies**: Docker + containerización

**¿Preguntas? ¿Problemas con Ollama?**

**¡Nos vemos en el Tutorial 4: Scaling to 10k+ concurrent users!** 📈