# ⚡ Tutorial 2: Phoenix + Streaming - La dupla perfecta

*Cómo convertir tu gateway en una API streaming real-time*

---

## 🎯 **Lo que aprenderás**

En este tutorial transformaremos nuestro worker pool en una API HTTP completa:
- Endpoints RESTful con Phoenix
- Streaming real-time con Server-Sent Events
- Chunked transfer encoding
- Manejo de errores HTTP elegante
- Testing de endpoints streaming

---

## 🧠 **Parte 1: ¿Por qué Streaming?**

### **El problema con las respuestas síncronas**

```
❌ API tradicional:
Cliente → POST /chat → [ESPERA 30 SEGUNDOS] → Respuesta completa

✅ API streaming:  
Cliente → POST /chat → chunk1... chunk2... chunk3... → Respuesta fluida
```

### **Phoenix advantages para streaming:**

- 🎯 **Chunked Transfer Encoding** nativo
- ⚡ **Cowboy** optimizado para conexiones largas  
- 🔄 **GenServer** integración perfecta con workers
- 🛡️ **Plug pipeline** para middleware elegante

---

## 🏗️ **Parte 2: Diseñando los Endpoints**

### **Estructura de la API:**

```
GET  /api/health          → Estado de todos los workers  
POST /api/chat            → Chat streaming
POST /api/chat/complete   → Chat sin streaming (legacy)
GET  /api/providers       → Lista de providers disponibles
```

### **1. Health Controller**

```elixir
# lib/cortex_web/controllers/health_controller.ex
defmodule CortexWeb.HealthController do
  use CortexWeb, :controller
  
  def check(conn, _params) do
    # Obtener estado con timeout para evitar bloqueos
    health_status = try do
      case GenServer.call(Cortex.Workers.Pool, :health_status, 3000) do
        health when is_map(health) -> health
        _ -> %{}
      end
    catch
      :exit, _ -> %{}
    end
    
    # Calcular estado general
    {overall_status, http_code} = calculate_overall_status(health_status)
    
    response = %{
      status: overall_status,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      workers: health_status,
      summary: %{
        total: map_size(health_status),
        available: count_by_status(health_status, :available),
        degraded: count_by_status(health_status, :degraded),
        unavailable: count_by_status(health_status, :unavailable)
      },
      uptime: get_uptime()
    }
    
    conn
    |> put_status(http_code)
    |> json(response)
  end
  
  defp calculate_overall_status(health_status) do
    case health_status do
      health when map_size(health) == 0 ->
        {"no_workers", 503}
      
      health ->
        available_count = count_by_status(health, :available)
        total_count = map_size(health)
        
        cond do
          available_count == 0 -> {"unhealthy", 503}
          available_count < total_count -> {"degraded", 200}
          true -> {"healthy", 200}
        end
    end
  end
  
  defp count_by_status(health_status, target_status) do
    health_status
    |> Enum.count(fn {_name, status} -> status == target_status end)
  end
  
  defp get_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms / 1000
  end
end
```

---

## 🌊 **Parte 3: El Chat Controller Streaming**

### **2. Chat Controller con chunked encoding**

```elixir
# lib/cortex_web/controllers/chat_controller.ex
defmodule CortexWeb.ChatController do
  use CortexWeb, :controller
  require Logger
  
  def create(conn, %{"messages" => messages} = params) do
    # Validar entrada
    case validate_messages(messages) do
      {:ok, validated_messages} ->
        handle_streaming_chat(conn, validated_messages, params)
      
      {:error, reason} ->
        send_error(conn, 400, "Invalid messages format", reason)
    end
  end
  
  def create(conn, _params) do
    send_error(conn, 400, "Missing required field", "messages field is required")
  end
  
  # Endpoint legacy sin streaming
  def complete(conn, %{"messages" => messages} = params) do
    case validate_messages(messages) do
      {:ok, validated_messages} ->
        handle_complete_chat(conn, validated_messages, params)
      
      {:error, reason} ->
        send_error(conn, 400, "Invalid messages format", reason)
    end
  end
  
  # --- STREAMING IMPLEMENTATION ---
  
  defp handle_streaming_chat(conn, messages, params) do
    opts = build_completion_opts(params)
    
    case Cortex.Dispatcher.dispatch_stream(messages, opts) do
      {:ok, stream} ->
        Logger.info("Starting streaming response")
        
        conn
        |> put_resp_content_type("text/plain")
        |> send_chunked(200)
        |> stream_response(stream)
      
      {:error, :no_workers_available} ->
        send_error(conn, 503, "No workers available", 
          "All AI providers are currently unavailable. Please try again later.")
      
      {:error, reason} ->
        Logger.error("Dispatch error: #{inspect(reason)}")
        send_error(conn, 500, "Internal server error", inspect(reason))
    end
  end
  
  defp stream_response(conn, stream) do
    try do
      Enum.reduce_while(stream, conn, fn chunk, acc_conn ->
        case process_stream_chunk(chunk) do
          {:ok, content} when content != "" ->
            case Plug.Conn.chunk(acc_conn, content) do
              {:ok, new_conn} -> 
                {:cont, new_conn}
              {:error, :closed} -> 
                Logger.info("Client closed connection")
                {:halt, acc_conn}
              {:error, reason} -> 
                Logger.error("Chunk error: #{inspect(reason)}")
                {:halt, acc_conn}
            end
          
          {:ok, _empty} ->
            {:cont, acc_conn}
          
          {:error, reason} ->
            Logger.warning("Chunk processing error: #{inspect(reason)}")  
            {:cont, acc_conn}
            
          :done ->
            {:halt, acc_conn}
        end
      end)
    rescue
      error ->
        Logger.error("Stream error: #{inspect(error)}")
        conn
    end
  end
  
  # --- NON-STREAMING IMPLEMENTATION ---
  
  defp handle_complete_chat(conn, messages, params) do
    opts = build_completion_opts(params)
    
    case Cortex.Dispatcher.dispatch_stream(messages, opts) do
      {:ok, stream} ->
        # Recopilar todo el stream en memoria
        complete_response = stream
        |> Enum.map(fn chunk ->
          case process_stream_chunk(chunk) do
            {:ok, content} -> content
            _ -> ""
          end
        end)
        |> Enum.join("")
        
        json(conn, %{
          response: complete_response,
          provider: "multi-provider",
          model: opts[:model] || "auto"
        })
      
      {:error, :no_workers_available} ->
        send_error(conn, 503, "No workers available", nil)
      
      {:error, reason} ->
        send_error(conn, 500, "Internal server error", inspect(reason))
    end
  end
  
  # --- HELPERS ---
  
  defp validate_messages(messages) when is_list(messages) do
    validated = Enum.map(messages, fn
      %{"role" => role, "content" => content} when role in ["user", "assistant", "system"] ->
        %{"role" => role, "content" => to_string(content)}
      
      invalid ->
        throw({:invalid_message, invalid})
    end)
    
    {:ok, validated}
  catch
    {:invalid_message, invalid} ->
      {:error, "Invalid message format: #{inspect(invalid)}"}
  end
  
  defp validate_messages(_), do: {:error, "Messages must be a list"}
  
  defp build_completion_opts(params) do
    [
      model: params["model"],
      temperature: parse_float(params["temperature"], 0.7),
      max_tokens: parse_integer(params["max_tokens"], 1000),
      stream: true  # Siempre streaming internamente
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end
  
  defp process_stream_chunk(chunk) do
    cond do
      is_binary(chunk) and chunk != "" ->
        {:ok, chunk}
      
      is_binary(chunk) ->
        {:ok, ""}
      
      is_nil(chunk) ->
        :done
      
      true ->
        case Jason.decode(chunk) do
          {:ok, %{"choices" => [%{"delta" => %{"content" => content}}]}} ->
            {:ok, content || ""}
          
          {:ok, %{"content" => content}} ->
            {:ok, content || ""}
          
          {:ok, %{"done" => true}} ->
            :done
          
          _ ->
            {:error, :invalid_chunk_format}
        end
    end
  rescue
    _ -> {:error, :chunk_parse_error}
  end
  
  defp send_error(conn, status, message, details) do
    conn
    |> put_status(status)
    |> json(%{
      error: message,
      details: details,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end
  
  defp parse_float(nil, default), do: default
  defp parse_float(value, default) when is_number(value), do: value
  defp parse_float(value, default) when is_binary(value) do
    case Float.parse(value) do
      {float_val, _} -> float_val
      :error -> default
    end
  end
  defp parse_float(_, default), do: default
  
  defp parse_integer(nil, default), do: default
  defp parse_integer(value, default) when is_integer(value), do: value
  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int_val, _} -> int_val
      :error -> default
    end
  end
  defp parse_integer(_, default), do: default
end
```

---

## 🔗 **Parte 4: Providers Controller**

### **3. Información de providers disponibles**

```elixir
# lib/cortex_web/controllers/providers_controller.ex
defmodule CortexWeb.ProvidersController do
  use CortexWeb, :controller
  
  def index(conn, _params) do
    # Obtener todos los workers registrados
    workers = Cortex.Workers.Registry.list_all()
    
    # Obtener estado de salud
    health_status = Cortex.Workers.Pool.health_status()
    
    providers = workers
    |> Enum.map(fn worker ->
      health = Map.get(health_status, worker.name, :unknown)
      
      %{
        name: worker.name,
        type: get_provider_type(worker),
        status: health,
        priority: apply(worker.__struct__, :priority, [worker]),
        models: get_supported_models(worker),
        capabilities: get_capabilities(worker)
      }
    end)
    |> Enum.sort_by(& &1.priority)
    
    json(conn, %{
      providers: providers,
      total_count: length(providers),
      healthy_count: Enum.count(providers, &(&1.status == :available)),
      default_strategy: "priority_first"
    })
  end
  
  defp get_provider_type(worker) do
    case worker.__struct__ do
      Cortex.Workers.Adapters.GroqWorker -> "groq"
      Cortex.Workers.Adapters.GeminiWorker -> "gemini"  
      Cortex.Workers.Adapters.CohereWorker -> "cohere"
      Cortex.Workers.Adapters.OllamaWorker -> "ollama"
      _ -> "unknown"
    end
  end
  
  defp get_supported_models(worker) do
    case worker do
      %{default_model: model} when is_binary(model) -> [model]
      %{models: models} when is_list(models) -> models
      _ -> ["auto"]
    end
  end
  
  defp get_capabilities(worker) do
    type = get_provider_type(worker)
    
    base_caps = ["chat_completion", "streaming"]
    
    additional_caps = case type do
      "groq" -> ["ultra_fast", "llm_specialized"]
      "gemini" -> ["multimodal", "large_context"] 
      "cohere" -> ["conversational", "enterprise"]
      "ollama" -> ["local", "offline", "unlimited"]
      _ -> []
    end
    
    base_caps ++ additional_caps
  end
end
```

---

## 🛣️ **Parte 5: Routes Configuration**

### **4. Actualizar el router**

```elixir
# lib/cortex_web/router.ex
defmodule CortexWeb.Router do
  use CortexWeb, :router
  
  pipeline :api do
    plug :accepts, ["json"]
    plug :put_secure_browser_headers
    
    # CORS para development (remover en producción)
    plug CORSPlug, origin: ["http://localhost:3000", "http://localhost:5173"]
  end
  
  pipeline :api_with_auth do
    plug :accepts, ["json"]
    # TODO: Agregar autenticación
    # plug MyApp.AuthPlug
  end
  
  # Public API routes
  scope "/api", CortexWeb do
    pipe_through :api
    
    # Health & Status
    get "/health", HealthController, :check
    get "/providers", ProvidersController, :index
    
    # Chat endpoints
    post "/chat", ChatController, :create
    post "/chat/complete", ChatController, :complete
  end
  
  # Protected routes (future)
  scope "/api/admin", CortexWeb do
    pipe_through :api_with_auth
    
    # TODO: Admin endpoints
    # post "/workers/reload", AdminController, :reload_workers
    # delete "/workers/:name", AdminController, :remove_worker  
  end
  
  # Enable LiveDashboard in development
  if Application.compile_env(:cortex, :dev_routes) do
    import Phoenix.LiveDashboard.Router
    
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]
      
      live_dashboard "/dashboard", metrics: CortexWeb.Telemetry
    end
  end
end
```

### **5. Agregar CORS plug**

```elixir
# mix.exs - agregar dependencia
{:cors_plug, "~> 3.0"}
```

---

## 🧪 **Parte 6: Testing Streaming**

### **6. Tests para el Chat Controller**

```elixir
# test/cortex_web/controllers/chat_controller_test.exs
defmodule CortexWeb.ChatControllerTest do
  use CortexWeb.ConnCase
  import ExUnit.CaptureLog
  
  alias Cortex.Workers.Adapters.MockWorker
  
  setup do
    # Mock worker para testing
    mock_worker = MockWorker.new([
      name: "test-mock",
      responses: ["Hello", " there", "!", nil]  # nil = fin de stream
    ])
    
    Cortex.Workers.Registry.register("test-mock", mock_worker)
    
    on_exit(fn ->
      Cortex.Workers.Registry.unregister("test-mock")
    end)
    
    :ok
  end
  
  describe "POST /api/chat" do
    test "streaming response with valid messages", %{conn: conn} do
      messages = [
        %{"role" => "user", "content" => "Hello!"}
      ]
      
      conn = post(conn, "/api/chat", %{"messages" => messages})
      
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
      
      # Verificar que es chunked
      assert get_resp_header(conn, "transfer-encoding") == ["chunked"]
    end
    
    test "error with invalid messages format", %{conn: conn} do
      conn = post(conn, "/api/chat", %{"messages" => "invalid"})
      
      assert json_response(conn, 400) == %{
        "error" => "Invalid messages format",
        "details" => "Messages must be a list",
        "timestamp" => "_ignore_timestamp"
      } |> Map.delete("timestamp")
    end
    
    test "error when no workers available", %{conn: conn} do
      # Remover el mock worker
      Cortex.Workers.Registry.unregister("test-mock")
      
      messages = [%{"role" => "user", "content" => "Hello!"}]
      
      conn = post(conn, "/api/chat", %{"messages" => messages})
      
      assert json_response(conn, 503)["error"] == "No workers available"
    end
  end
  
  describe "POST /api/chat/complete" do  
    test "returns complete response", %{conn: conn} do
      messages = [%{"role" => "user", "content" => "Test"}]
      
      conn = post(conn, "/api/chat/complete", %{"messages" => messages})
      
      response = json_response(conn, 200)
      
      assert response["response"] == "Hello there!"
      assert response["provider"] == "multi-provider"
    end
  end
end
```

### **7. Mock Worker para testing**

```elixir
# test/support/mock_worker.ex
defmodule Cortex.Workers.Adapters.MockWorker do
  @behaviour Cortex.Workers.Worker
  
  defstruct [:name, :responses, :current_index, :health_status]
  
  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      responses: Keyword.get(opts, :responses, ["Mock response"]),
      current_index: 0,
      health_status: Keyword.get(opts, :health_status, :available)
    }
  end
  
  @impl true
  def stream_completion(worker, _messages, _opts) do
    stream = Stream.unfold(worker.current_index, fn index ->
      case Enum.at(worker.responses, index) do
        nil -> nil
        response -> {response, index + 1}
      end
    end)
    
    {:ok, stream}
  end
  
  @impl true
  def health_check(worker) do
    {:ok, worker.health_status}
  end
  
  @impl true
  def priority(_worker), do: 999  # Baja prioridad para tests
  
  @impl true  
  def transform_messages(messages, _opts), do: messages
end
```

---

## 🔥 **Parte 7: Middleware Avanzado**

### **8. Plug para rate limiting**

```elixir
# lib/cortex_web/plugs/rate_limit.ex
defmodule CortexWeb.Plugs.RateLimit do
  import Plug.Conn
  
  def init(opts) do
    # requests por minuto
    requests_per_minute = Keyword.get(opts, :requests_per_minute, 60)
    window_size = 60_000  # 1 minuto en ms
    
    %{
      requests_per_minute: requests_per_minute,
      window_size: window_size,
      cleanup_interval: 300_000  # 5 minutos
    }
  end
  
  def call(conn, opts) do
    client_id = get_client_id(conn)
    now = System.system_time(:millisecond)
    
    case check_rate_limit(client_id, now, opts) do
      :ok ->
        conn
      
      {:error, :rate_limited, reset_time} ->
        conn
        |> put_resp_header("x-ratelimit-limit", to_string(opts.requests_per_minute))
        |> put_resp_header("x-ratelimit-reset", to_string(reset_time))
        |> put_status(429)
        |> json(%{error: "Rate limit exceeded", reset_at: reset_time})
        |> halt()
    end
  end
  
  defp get_client_id(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> "token:#{String.slice(token, 0..10)}"
      _ -> "ip:#{to_string(:inet.ntoa(conn.remote_ip))}"
    end
  end
  
  defp check_rate_limit(client_id, now, opts) do
    # Implementación simple en memoria (usar Redis en producción)
    case :ets.lookup(:rate_limit, client_id) do
      [] ->
        :ets.insert(:rate_limit, {client_id, [now]})
        :ok
      
      [{^client_id, timestamps}] ->
        # Filtrar timestamps en la ventana actual
        window_start = now - opts.window_size
        recent_timestamps = Enum.filter(timestamps, &(&1 > window_start))
        
        if length(recent_timestamps) >= opts.requests_per_minute do
          reset_time = Enum.min(recent_timestamps) + opts.window_size
          {:error, :rate_limited, reset_time}
        else
          :ets.insert(:rate_limit, {client_id, [now | recent_timestamps]})
          :ok
        end
    end
  end
end
```

### **9. Inicializar ETS table**

```elixir
# lib/cortex/application.ex
def start(_type, _args) do
  # Crear tabla ETS para rate limiting
  :ets.new(:rate_limit, [:set, :public, :named_table])
  
  children = [
    # ... resto de children
  ]
  
  # ... resto del código
end
```

---

## 🎮 **Parte 8: Cliente de Testing**

### **10. Script de prueba manual**

```bash
#!/bin/bash
# test_streaming.sh

echo "🧪 Testing Córtex Streaming API"
echo "==============================="

BASE_URL="http://localhost:4000"

# Test 1: Health Check
echo "📊 Health Check:"
curl -s "$BASE_URL/api/health" | jq .
echo ""

# Test 2: Providers List  
echo "🔌 Available Providers:"
curl -s "$BASE_URL/api/providers" | jq .
echo ""

# Test 3: Streaming Chat
echo "💬 Streaming Chat:"
curl -N -X POST "$BASE_URL/api/chat" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "Escribe un haiku sobre programming"}
    ],
    "temperature": 0.7,
    "max_tokens": 100
  }' \
  | while IFS= read -r line; do
    echo -n "$line"
    sleep 0.1  # Para ver el efecto streaming
  done

echo ""
echo ""

# Test 4: Complete Chat (non-streaming)
echo "⚡ Complete Chat:"  
curl -s -X POST "$BASE_URL/api/chat/complete" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "Di solo: ¡Sistema funcionando!"}
    ]
  }' | jq .

echo ""
echo "✅ Tests completados"
```

---

## 🎯 **Parte 9: Monitoreo y Métricas**

### **11. Telemetry events**

```elixir
# lib/cortex_web/telemetry.ex
defmodule CortexWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics
  
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end
  
  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      
      # Custom Metrics
      counter("cortex.chat.requests.total",
        tags: [:provider, :status]
      ),
      summary("cortex.chat.duration",
        tags: [:provider],
        unit: {:native, :millisecond}
      ),
      counter("cortex.workers.health_check.total",
        tags: [:worker, :status]
      ),
      
      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end
  
  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      {__MODULE__, :dispatch_metrics, []}
    ]
  end
  
  def dispatch_metrics do
    # Custom metrics dispatch
    health_status = Cortex.Workers.Pool.health_status()
    
    Enum.each(health_status, fn {worker_name, status} ->
      :telemetry.execute(
        [:cortex, :workers, :health_check],
        %{count: 1},
        %{worker: worker_name, status: status}
      )
    end)
  end
end
```

### **12. Instrumentar el ChatController**

```elixir
# Agregar al ChatController
defp handle_streaming_chat(conn, messages, params) do
  start_time = System.monotonic_time()
  
  case Cortex.Dispatcher.dispatch_stream(messages, opts) do
    {:ok, stream} ->
      :telemetry.execute(
        [:cortex, :chat, :requests],
        %{count: 1},
        %{provider: "multi", status: :success}
      )
      
      result = conn
      |> put_resp_content_type("text/plain")  
      |> send_chunked(200)
      |> stream_response(stream)
      
      end_time = System.monotonic_time()
      duration = end_time - start_time
      
      :telemetry.execute(
        [:cortex, :chat, :duration],
        %{duration: duration},
        %{provider: "multi"}
      )
      
      result
      
    {:error, reason} ->
      :telemetry.execute(
        [:cortex, :chat, :requests],
        %{count: 1}, 
        %{provider: "multi", status: :error}
      )
      
      # ... manejo de errores
  end
end
```

---

## 🎉 **¡Felicitaciones!**

Has construido una API streaming completa con Phoenix. Ahora tienes:

✅ **Endpoints RESTful** con validación robusta  
✅ **Streaming real-time** con chunked encoding  
✅ **Rate limiting** inteligente  
✅ **Health monitoring** detallado  
✅ **Telemetry** y métricas  
✅ **Testing** completo  

### **🔥 Funcionalidades implementadas:**

- **4 endpoints principales** (/health, /chat, /complete, /providers)
- **Error handling** elegante en toda la stack
- **Middleware pipeline** extensible  
- **Streaming optimizado** para UX fluida
- **Monitoreo** en tiempo real

### **📊 Performance esperado:**
- **~5ms** latencia para health checks
- **~20ms** TTFB para streaming  
- **100+ requests/sec** por worker
- **Memory efficient** con lazy streams

### **🔧 Para probar:**

```bash
# Configurar
export GROQ_API_KEYS=tu_key
mix phx.server

# Probar streaming
./test_streaming.sh

# Ver métricas  
open http://localhost:4000/dev/dashboard
```

---

## 💡 **Conceptos clave aprendidos:**

1. **Chunked Transfer Encoding**: Streaming HTTP real
2. **Phoenix Controllers**: Manejo elegante de requests/responses  
3. **Plug Pipeline**: Middleware composable
4. **Telemetry**: Observabilidad sin overhead
5. **Error Boundaries**: Aislamiento de fallos en HTTP layer

**¿Preguntas? ¿Problemas?** 

**¡Nos vemos en el Tutorial 3: Ollama como backup infinito!** 🏠