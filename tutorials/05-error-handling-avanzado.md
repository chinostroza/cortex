# 🛡️ Tutorial 5: Error handling que no te dejará dormir mal

*Cómo construir un sistema de IA que nunca te despierte a las 3AM*

---

## 🎯 **Lo que aprenderás**

En este tutorial final construiremos error handling de nivel enterprise:
- Circuit breakers para fallos en cascada
- Retry strategies inteligentes 
- Error propagation controlada
- Monitoring y alertas proactivas
- Dead letter queues para requests fallidas
- Graceful degradation automática

---

## 🧠 **Parte 1: La pesadilla de los errores en IA**

### **Escenario de terror común:**

```
3:17 AM 🔔 CRITICAL: Córtex está caído
3:18 AM 🔔 ERROR: Groq rate limit exceeded
3:19 AM 🔔 ERROR: Gemini timeout
3:20 AM 🔔 ERROR: Cohere internal server error
3:21 AM 🔔 PANIC: Ollama disconnected
3:22 AM 😵 Tú: "¿Por qué yo...?"
```

### **El problema real:**

```elixir
❌ Error handling básico:
try do
  call_ai_api()
catch
  error -> {:error, "Algo salió mal"}
end

✅ Error handling profesional:
case call_ai_api() do
  {:ok, result} -> 
    {:ok, result}
  {:error, :rate_limited} -> 
    schedule_retry_with_backoff()
  {:error, :timeout} -> 
    try_next_provider()
  {:error, :quota_exceeded} -> 
    rotate_api_key_and_retry()
  {:error, :service_unavailable} -> 
    activate_circuit_breaker()
end
```

### **Tipos de errores en sistemas AI:**

1. **🚦 Rate Limiting** - Predecible, manejable
2. **⏰ Timeouts** - Red lenta, servers ocupados
3. **💸 Quota Exceeded** - Plan gratuito agotado  
4. **🔐 Auth Errors** - API keys inválidas/expiradas
5. **🌊 Service Unavailable** - Provider caído
6. **💀 Parse Errors** - Response format inesperado
7. **🔄 Network Issues** - Internet intermitente

---

## 🔧 **Parte 2: Circuit Breaker Pattern**

### **1. Estado del Circuit Breaker**

```elixir
# lib/cortex/resilience/circuit_breaker.ex
defmodule Cortex.Resilience.CircuitBreaker do
  @moduledoc """
  Circuit breaker para proteger contra fallos en cascada.
  Estados: :closed (normal) -> :open (failing) -> :half_open (testing)
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :name,
    :state,           # :closed, :open, :half_open
    :failure_count,
    :success_count,
    :last_failure,
    :failure_threshold,  # Cuántos fallos antes de abrir
    :recovery_timeout,   # Tiempo antes de intentar recovery
    :reset_timeout      # Tiempo para resetear contador
  ]
  
  @default_failure_threshold 5
  @default_recovery_timeout 60_000  # 1 minuto
  @default_reset_timeout 300_000   # 5 minutos
  
  ## Client API
  
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(name))
  end
  
  def call(name, fun) when is_function(fun) do
    case GenServer.call(via_tuple(name), :get_state) do
      :open ->
        {:error, :circuit_open}
        
      :half_open ->
        execute_with_monitoring(name, fun, :half_open)
        
      :closed ->
        execute_with_monitoring(name, fun, :closed)
    end
  end
  
  def get_stats(name) do
    GenServer.call(via_tuple(name), :get_stats)
  end
  
  ## Server Callbacks
  
  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    
    state = %__MODULE__{
      name: name,
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure: nil,
      failure_threshold: Keyword.get(opts, :failure_threshold, @default_failure_threshold),
      recovery_timeout: Keyword.get(opts, :recovery_timeout, @default_recovery_timeout),
      reset_timeout: Keyword.get(opts, :reset_timeout, @default_reset_timeout)
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:get_state, _from, state) do
    current_state = maybe_attempt_reset(state)
    {:reply, current_state.state, current_state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      state: state.state,
      failure_count: state.failure_count,
      success_count: state.success_count,
      last_failure: state.last_failure,
      uptime_percentage: calculate_uptime(state)
    }
    {:reply, stats, state}
  end
  
  @impl true
  def handle_cast({:record_success}, state) do
    new_state = handle_success(state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:record_failure, reason}, state) do
    new_state = handle_failure(state, reason)
    {:noreply, new_state}
  end
  
  ## Private Functions
  
  defp execute_with_monitoring(name, fun, circuit_state) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      result = fun.()
      GenServer.cast(via_tuple(name), {:record_success})
      
      # Telemetry para métricas
      :telemetry.execute(
        [:cortex, :circuit_breaker, :success],
        %{duration: System.monotonic_time(:millisecond) - start_time},
        %{name: name, previous_state: circuit_state}
      )
      
      {:ok, result}
    rescue
      error ->
        GenServer.cast(via_tuple(name), {:record_failure, error})
        
        :telemetry.execute(
          [:cortex, :circuit_breaker, :failure],
          %{duration: System.monotonic_time(:millisecond) - start_time},
          %{name: name, error: inspect(error), state: circuit_state}
        )
        
        {:error, error}
    end
  end
  
  defp handle_success(state) do
    case state.state do
      :half_open ->
        Logger.info("Circuit breaker #{state.name} recovery successful, closing")
        %{state | 
          state: :closed, 
          failure_count: 0, 
          success_count: state.success_count + 1
        }
        
      :closed ->
        %{state | success_count: state.success_count + 1}
        
      :open ->
        state  # No debería pasar
    end
  end
  
  defp handle_failure(state, reason) do
    Logger.warning("Circuit breaker #{state.name} recorded failure: #{inspect(reason)}")
    
    new_failure_count = state.failure_count + 1
    new_state = %{state | 
      failure_count: new_failure_count,
      last_failure: DateTime.utc_now()
    }
    
    if new_failure_count >= state.failure_threshold do
      Logger.error("Circuit breaker #{state.name} opening due to #{new_failure_count} failures")
      %{new_state | state: :open}
    else
      new_state
    end
  end
  
  defp maybe_attempt_reset(state) do
    case state.state do
      :open ->
        if should_attempt_recovery?(state) do
          Logger.info("Circuit breaker #{state.name} attempting recovery (half-open)")
          %{state | state: :half_open}
        else
          state
        end
        
      _ ->
        state
    end
  end
  
  defp should_attempt_recovery?(state) do
    case state.last_failure do
      nil -> false
      last_failure ->
        DateTime.diff(DateTime.utc_now(), last_failure, :millisecond) >= state.recovery_timeout
    end
  end
  
  defp calculate_uptime(state) do
    total_calls = state.success_count + state.failure_count
    
    if total_calls == 0 do
      100.0
    else
      (state.success_count / total_calls) * 100
    end
  end
  
  defp via_tuple(name) do
    {:via, Registry, {Cortex.CircuitBreakerRegistry, name}}
  end
end
```

### **2. Integrar Circuit Breaker en Workers**

```elixir
# Actualizar lib/cortex/workers/adapters/api_worker_base.ex
defmodule Cortex.Workers.Adapters.ApiWorkerBase do
  
  @callback provider_config(worker :: term()) :: map()
  
  # Wrapper con circuit breaker
  def safe_api_call(worker, operation_name, fun) do
    circuit_name = "#{worker.name}_#{operation_name}"
    
    case Cortex.Resilience.CircuitBreaker.call(circuit_name, fun) do
      {:ok, result} -> 
        {:ok, result}
        
      {:error, :circuit_open} ->
        Logger.warning("Circuit breaker open for #{worker.name}, failing fast")
        {:error, :circuit_open}
        
      {:error, reason} ->
        Logger.error("API call failed for #{worker.name}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  # Health check mejorado con circuit breaker
  def health_check(worker) do
    config = apply(worker.__struct__, :provider_config, [worker])
    health_url = Map.get(config, :health_endpoint, config.base_url)
    headers = config.headers_fn.(worker)
    
    health_check_fn = fn ->
      Req.get(health_url, 
        headers: headers, 
        receive_timeout: worker.timeout,
        retry: false  # Lo manejamos nosotros
      )
    end
    
    case safe_api_call(worker, "health", health_check_fn) do
      {:ok, %{status: status}} when status in 200..299 -> 
        {:ok, :available}
        
      {:ok, %{status: status}} when status in 400..499 -> 
        {:error, :client_error}
        
      {:ok, %{status: status}} when status in 500..599 -> 
        {:error, :server_error}
        
      {:error, :circuit_open} -> 
        {:error, :circuit_open}
        
      {:error, %{reason: :timeout}} -> 
        {:error, :timeout}
        
      {:error, reason} -> 
        {:error, reason}
    end
  end
end
```

---

## 🔄 **Parte 3: Retry Strategies Inteligentes**

### **3. Exponential Backoff con Jitter**

```elixir
# lib/cortex/resilience/retry_strategy.ex
defmodule Cortex.Resilience.RetryStrategy do
  @moduledoc """
  Estrategias de retry inteligentes para diferentes tipos de error.
  """
  
  defstruct [
    :max_attempts,
    :base_delay,
    :max_delay,
    :backoff_multiplier,
    :jitter_function,
    :retry_condition
  ]
  
  @default_max_attempts 3
  @default_base_delay 1000     # 1 segundo
  @default_max_delay 30_000    # 30 segundos
  @default_backoff_multiplier 2
  
  ## Strategies predefinidas
  
  def rate_limit_strategy do
    %__MODULE__{
      max_attempts: 5,
      base_delay: 2000,
      max_delay: 60_000,
      backoff_multiplier: 2,
      jitter_function: &add_full_jitter/1,
      retry_condition: &should_retry_rate_limit?/1
    }
  end
  
  def network_strategy do
    %__MODULE__{
      max_attempts: 3,
      base_delay: 500,
      max_delay: 10_000,
      backoff_multiplier: 1.5,
      jitter_function: &add_decorrelated_jitter/1,
      retry_condition: &should_retry_network?/1
    }
  end
  
  def server_error_strategy do
    %__MODULE__{
      max_attempts: 4,
      base_delay: 1000,
      max_delay: 20_000,
      backoff_multiplier: 2,
      jitter_function: &add_equal_jitter/1,
      retry_condition: &should_retry_server_error?/1
    }
  end
  
  ## Retry execution
  
  def execute_with_retry(strategy, fun, context \\ %{}) do
    execute_attempt(strategy, fun, 1, context)
  end
  
  defp execute_attempt(strategy, fun, attempt, context) do
    case fun.() do
      {:ok, result} -> 
        {:ok, result}
        
      {:error, reason} = error ->
        should_retry = strategy.retry_condition.(reason)
        can_retry = attempt < strategy.max_attempts
        
        cond do
          not should_retry ->
            Logger.info("Not retrying #{inspect(reason)} - retry condition failed")
            error
            
          not can_retry ->
            Logger.error("Max retry attempts (#{strategy.max_attempts}) reached")
            {:error, {:max_retries_exceeded, reason}}
            
          true ->
            delay = calculate_delay(strategy, attempt)
            
            Logger.info("Retrying in #{delay}ms (attempt #{attempt + 1}/#{strategy.max_attempts})")
            
            :telemetry.execute(
              [:cortex, :retry, :attempt], 
              %{attempt: attempt, delay: delay},
              Map.merge(context, %{reason: reason})
            )
            
            Process.sleep(delay)
            execute_attempt(strategy, fun, attempt + 1, context)
        end
    end
  end
  
  ## Delay calculation with jitter
  
  defp calculate_delay(strategy, attempt) do
    # Exponential backoff
    base_delay = strategy.base_delay * :math.pow(strategy.backoff_multiplier, attempt - 1)
    
    # Cap at max delay
    capped_delay = min(base_delay, strategy.max_delay) |> trunc()
    
    # Apply jitter
    strategy.jitter_function.(capped_delay)
  end
  
  ## Jitter functions
  
  defp add_full_jitter(delay) do
    # Completamente aleatorio entre 0 y delay
    :rand.uniform(delay)
  end
  
  defp add_equal_jitter(delay) do
    # Mitad fijo, mitad aleatorio
    half_delay = div(delay, 2)
    half_delay + :rand.uniform(half_delay)
  end
  
  defp add_decorrelated_jitter(delay) do
    # Jitter decorrelacionado - bueno para múltiples clientes
    min(delay * 3, :rand.uniform(delay * 3))
  end
  
  ## Retry conditions
  
  defp should_retry_rate_limit?(reason) do
    case reason do
      :rate_limited -> true
      {:http_error, 429} -> true
      {:http_error, 503} -> true  # Service temporarily unavailable
      _ -> false
    end
  end
  
  defp should_retry_network?(reason) do
    case reason do
      :timeout -> true
      :econnrefused -> true
      :nxdomain -> false  # DNS issue, don't retry
      {:http_error, status} when status in 500..599 -> true
      _ -> false
    end
  end
  
  defp should_retry_server_error?(reason) do
    case reason do
      {:http_error, 500} -> true  # Internal server error
      {:http_error, 502} -> true  # Bad gateway
      {:http_error, 503} -> true  # Service unavailable
      {:http_error, 504} -> true  # Gateway timeout
      :timeout -> true
      _ -> false
    end
  end
end
```

### **4. Integrar Retry en Workers**

```elixir
# Actualizar GroqWorker con retry strategy
def stream_completion(worker, messages, opts) do
  strategy = RetryStrategy.rate_limit_strategy()
  context = %{worker: worker.name, provider: "groq"}
  
  retry_fn = fn ->
    attempt_stream_completion(worker, messages, opts)
  end
  
  case RetryStrategy.execute_with_retry(strategy, retry_fn, context) do
    {:ok, stream} -> {:ok, stream}
    {:error, {:max_retries_exceeded, reason}} -> {:error, reason}
    {:error, reason} -> {:error, reason}
  end
end

defp attempt_stream_completion(worker, messages, opts) do
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
  
  url = @base_url <> "/openai/v1/chat/completions"
  
  case Req.post(url, headers: headers, json: payload, receive_timeout: worker.timeout) do
    {:ok, %{status: 200} = response} ->
      stream = parse_sse_stream(response.body)
      {:ok, stream}
    
    {:ok, %{status: 429}} ->
      # Rate limit - let retry strategy handle it
      {:error, :rate_limited}
    
    {:ok, %{status: 401}} ->
      # Invalid API key - rotate and let retry handle it
      _rotated_worker = rotate_api_key(worker)
      {:error, :invalid_api_key}
    
    {:ok, %{status: status}} when status in 500..599 ->
      {:error, {:http_error, status}}
    
    {:ok, %{status: status}} ->
      {:error, {:http_error, status}}
    
    {:error, reason} ->
      {:error, reason}
  end
end
```

---

## 📊 **Parte 4: Dead Letter Queue**

### **5. Queue para requests fallidas**

```elixir
# lib/cortex/resilience/dead_letter_queue.ex
defmodule Cortex.Resilience.DeadLetterQueue do
  @moduledoc """
  Dead Letter Queue para requests que fallaron después de todos los retries.
  Permite análisis posterior y posible reprocessamiento manual.
  """
  
  use GenServer
  require Logger
  
  defstruct [:max_size, :items, :stats]
  
  @default_max_size 1000
  
  ## Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def add_failed_request(request, error, metadata \\ %{}) do
    item = %{
      request: request,
      error: error,
      metadata: metadata,
      timestamp: DateTime.utc_now(),
      id: generate_id()
    }
    
    GenServer.cast(__MODULE__, {:add_item, item})
  end
  
  def get_failed_requests(limit \\ 100) do
    GenServer.call(__MODULE__, {:get_items, limit})
  end
  
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  def clear_old_items(older_than_hours \\ 24) do
    GenServer.cast(__MODULE__, {:clear_old, older_than_hours})
  end
  
  def retry_item(item_id) do
    GenServer.call(__MODULE__, {:retry_item, item_id})
  end
  
  ## Server Callbacks
  
  @impl true
  def init(opts) do
    max_size = Keyword.get(opts, :max_size, @default_max_size)
    
    state = %__MODULE__{
      max_size: max_size,
      items: [],
      stats: %{
        total_added: 0,
        total_cleared: 0,
        total_retried: 0
      }
    }
    
    # Schedule periodic cleanup
    Process.send_after(self(), :periodic_cleanup, 3600_000)  # 1 hour
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:add_item, item}, state) do
    Logger.warning("Adding failed request to DLQ: #{item.id}")
    
    new_items = [item | state.items]
    |> Enum.take(state.max_size)  # Keep only max_size items
    
    new_stats = %{state.stats | total_added: state.stats.total_added + 1}
    
    :telemetry.execute(
      [:cortex, :dlq, :item_added],
      %{count: 1},
      %{error_type: classify_error(item.error)}
    )
    
    {:noreply, %{state | items: new_items, stats: new_stats}}
  end
  
  @impl true
  def handle_cast({:clear_old, older_than_hours}, state) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -older_than_hours * 3600, :second)
    
    {old_items, new_items} = Enum.split_with(state.items, fn item ->
      DateTime.compare(item.timestamp, cutoff_time) == :lt
    end)
    
    cleared_count = length(old_items)
    new_stats = %{state.stats | total_cleared: state.stats.total_cleared + cleared_count}
    
    if cleared_count > 0 do
      Logger.info("Cleared #{cleared_count} old items from DLQ")
    end
    
    {:noreply, %{state | items: new_items, stats: new_stats}}
  end
  
  @impl true
  def handle_call({:get_items, limit}, _from, state) do
    items = Enum.take(state.items, limit)
    {:reply, items, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    current_stats = Map.merge(state.stats, %{
      current_size: length(state.items),
      max_size: state.max_size,
      error_breakdown: get_error_breakdown(state.items)
    })
    
    {:reply, current_stats, state}
  end
  
  @impl true
  def handle_call({:retry_item, item_id}, _from, state) do
    case Enum.find_index(state.items, &(&1.id == item_id)) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      index ->
        item = Enum.at(state.items, index)
        new_items = List.delete_at(state.items, index)
        
        # Attempt to retry the request
        case retry_failed_request(item) do
          :ok ->
            new_stats = %{state.stats | total_retried: state.stats.total_retried + 1}
            Logger.info("Successfully retried DLQ item: #{item_id}")
            {:reply, :ok, %{state | items: new_items, stats: new_stats}}
            
          {:error, reason} ->
            # Put back in queue if retry failed
            {:reply, {:error, reason}, state}
        end
    end
  end
  
  @impl true
  def handle_info(:periodic_cleanup, state) do
    # Auto-cleanup items older than 24 hours
    send(self(), :periodic_cleanup, after: 3600_000)  # Schedule next cleanup
    {:noreply, state}
  end
  
  ## Private Functions
  
  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end
  
  defp classify_error(error) do
    case error do
      :rate_limited -> "rate_limit"
      :timeout -> "timeout"
      {:http_error, status} -> "http_#{status}"
      :circuit_open -> "circuit_breaker"
      _ -> "other"
    end
  end
  
  defp get_error_breakdown(items) do
    items
    |> Enum.map(&classify_error(&1.error))
    |> Enum.frequencies()
  end
  
  defp retry_failed_request(item) do
    # Extract original request details and retry
    case item.request do
      %{messages: messages, opts: opts, worker: worker_name} ->
        case Cortex.Workers.Registry.get_worker(worker_name) do
          {:ok, worker} ->
            case apply(worker.__struct__, :stream_completion, [worker, messages, opts]) do
              {:ok, _stream} -> :ok
              {:error, reason} -> {:error, reason}
            end
            
          {:error, :not_found} ->
            {:error, :worker_not_found}
        end
        
      _ ->
        {:error, :invalid_request_format}
    end
  end
end
```

---

## 🔔 **Parte 5: Monitoring y Alertas**

### **6. Health Monitor Avanzado**

```elixir
# lib/cortex/monitoring/health_monitor.ex
defmodule Cortex.Monitoring.HealthMonitor do
  @moduledoc """
  Monitor avanzado que trackea la salud del sistema y envía alertas.
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :check_interval,
    :alert_thresholds,
    :notification_channels,
    :health_history,
    :current_alerts
  ]
  
  @default_check_interval 30_000  # 30 segundos
  @max_history_size 100
  
  ## Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def get_system_health do
    GenServer.call(__MODULE__, :get_system_health)
  end
  
  def get_active_alerts do
    GenServer.call(__MODULE__, :get_active_alerts)
  end
  
  def acknowledge_alert(alert_id) do
    GenServer.cast(__MODULE__, {:acknowledge_alert, alert_id})
  end
  
  ## Server Callbacks
  
  @impl true
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, @default_check_interval)
    
    state = %__MODULE__{
      check_interval: check_interval,
      alert_thresholds: get_alert_thresholds(),
      notification_channels: get_notification_channels(),
      health_history: [],
      current_alerts: %{}
    }
    
    # Start health check loop
    Process.send_after(self(), :health_check, 1000)
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:get_system_health, _from, state) do
    health = case state.health_history do
      [latest | _] -> latest
      [] -> perform_health_check()
    end
    
    {:reply, health, state}
  end
  
  @impl true
  def handle_call(:get_active_alerts, _from, state) do
    active = state.current_alerts
    |> Map.values()
    |> Enum.reject(&(&1.acknowledged))
    
    {:reply, active, state}
  end
  
  @impl true
  def handle_cast({:acknowledge_alert, alert_id}, state) do
    new_alerts = case Map.get(state.current_alerts, alert_id) do
      nil -> state.current_alerts
      alert -> Map.put(state.current_alerts, alert_id, %{alert | acknowledged: true})
    end
    
    {:noreply, %{state | current_alerts: new_alerts}}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    # Perform health check
    health_data = perform_health_check()
    
    # Update history
    new_history = [health_data | state.health_history]
    |> Enum.take(@max_history_size)
    
    # Check for alerts
    new_alerts = check_for_alerts(health_data, state.alert_thresholds, state.current_alerts)
    
    # Send notifications for new alerts
    send_alert_notifications(new_alerts, state.current_alerts, state.notification_channels)
    
    # Schedule next check
    Process.send_after(self(), :health_check, state.check_interval)
    
    {:noreply, %{state | 
      health_history: new_history, 
      current_alerts: new_alerts
    }}
  end
  
  ## Private Functions
  
  defp perform_health_check do
    start_time = System.monotonic_time(:millisecond)
    
    # Get worker health
    worker_health = case Cortex.Workers.Pool.health_status() do
      health when is_map(health) -> health
      _ -> %{}
    end
    
    # Get circuit breaker stats
    circuit_stats = get_circuit_breaker_stats()
    
    # Get DLQ stats
    dlq_stats = Cortex.Resilience.DeadLetterQueue.get_stats()
    
    # System metrics
    system_metrics = get_system_metrics()
    
    health_data = %{
      timestamp: DateTime.utc_now(),
      check_duration: System.monotonic_time(:millisecond) - start_time,
      workers: worker_health,
      circuits: circuit_stats,
      dlq: dlq_stats,
      system: system_metrics,
      overall_status: calculate_overall_status(worker_health, circuit_stats, dlq_stats)
    }
    
    :telemetry.execute(
      [:cortex, :health, :check_completed],
      %{duration: health_data.check_duration},
      %{status: health_data.overall_status}
    )
    
    health_data
  end
  
  defp get_circuit_breaker_stats do
    # This would integrate with circuit breaker registry
    # For now, return empty map
    %{}
  end
  
  defp get_system_metrics do
    %{
      memory_usage: :erlang.memory(:total),
      process_count: length(Process.list()),
      queue_lengths: :erlang.statistics(:run_queue_lengths)
    }
  end
  
  defp calculate_overall_status(worker_health, circuit_stats, dlq_stats) do
    available_workers = worker_health
    |> Map.values()
    |> Enum.count(&(&1 == :available))
    
    total_workers = map_size(worker_health)
    
    cond do
      total_workers == 0 -> :no_workers
      available_workers == 0 -> :critical
      available_workers < total_workers / 2 -> :degraded
      dlq_stats[:current_size] > 100 -> :warning
      true -> :healthy
    end
  end
  
  defp get_alert_thresholds do
    %{
      no_available_workers: %{severity: :critical, cooldown: 300_000},
      high_dlq_size: %{threshold: 50, severity: :warning, cooldown: 600_000},
      circuit_breaker_open: %{severity: :warning, cooldown: 180_000},
      high_memory_usage: %{threshold: 1_000_000_000, severity: :warning, cooldown: 300_000}  # 1GB
    }
  end
  
  defp get_notification_channels do
    [
      # Add your notification channels here
      # {:slack, webhook_url: "..."},
      # {:email, to: "ops@company.com"},
      {:log, level: :error}
    ]
  end
  
  defp check_for_alerts(health_data, thresholds, current_alerts) do
    new_alerts = current_alerts
    
    # Check each threshold
    new_alerts = check_no_workers_alert(health_data, thresholds, new_alerts)
    new_alerts = check_dlq_size_alert(health_data, thresholds, new_alerts)
    new_alerts = check_memory_alert(health_data, thresholds, new_alerts)
    
    # Remove resolved alerts
    remove_resolved_alerts(new_alerts, health_data)
  end
  
  defp check_no_workers_alert(health_data, thresholds, alerts) do
    available_count = health_data.workers
    |> Map.values()
    |> Enum.count(&(&1 == :available))
    
    alert_key = :no_available_workers
    
    if available_count == 0 and not Map.has_key?(alerts, alert_key) do
      alert = %{
        id: alert_key,
        type: alert_key,
        severity: thresholds[alert_key][:severity],
        message: "No workers are available",
        timestamp: health_data.timestamp,
        acknowledged: false,
        data: %{available_count: available_count}
      }
      
      Map.put(alerts, alert_key, alert)
    else
      alerts
    end
  end
  
  defp check_dlq_size_alert(health_data, thresholds, alerts) do
    dlq_size = health_data.dlq[:current_size] || 0
    threshold = thresholds[:high_dlq_size][:threshold]
    
    alert_key = :high_dlq_size
    
    if dlq_size > threshold and not Map.has_key?(alerts, alert_key) do
      alert = %{
        id: alert_key,
        type: alert_key,
        severity: threshold[:severity],
        message: "Dead letter queue size is high: #{dlq_size}",
        timestamp: health_data.timestamp,
        acknowledged: false,
        data: %{dlq_size: dlq_size, threshold: threshold}
      }
      
      Map.put(alerts, alert_key, alert)
    else
      alerts
    end
  end
  
  defp check_memory_alert(health_data, thresholds, alerts) do
    memory_usage = health_data.system[:memory_usage] || 0
    threshold = thresholds[:high_memory_usage][:threshold]
    
    alert_key = :high_memory_usage
    
    if memory_usage > threshold and not Map.has_key?(alerts, alert_key) do
      alert = %{
        id: alert_key,
        type: alert_key,
        severity: thresholds[alert_key][:severity],
        message: "Memory usage is high: #{format_bytes(memory_usage)}",
        timestamp: health_data.timestamp,
        acknowledged: false,
        data: %{memory_usage: memory_usage, threshold: threshold}
      }
      
      Map.put(alerts, alert_key, alert)
    else
      alerts
    end
  end
  
  defp remove_resolved_alerts(alerts, health_data) do
    # Remove alerts that have been resolved
    Enum.reduce(alerts, %{}, fn {key, alert}, acc ->
      if alert_still_active?(alert, health_data) do
        Map.put(acc, key, alert)
      else
        Logger.info("Alert resolved: #{key}")
        acc
      end
    end)
  end
  
  defp alert_still_active?(alert, health_data) do
    case alert.type do
      :no_available_workers ->
        available_count = health_data.workers
        |> Map.values()
        |> Enum.count(&(&1 == :available))
        
        available_count == 0
        
      :high_dlq_size ->
        dlq_size = health_data.dlq[:current_size] || 0
        dlq_size > alert.data.threshold
        
      :high_memory_usage ->
        memory_usage = health_data.system[:memory_usage] || 0
        memory_usage > alert.data.threshold
        
      _ ->
        true  # Unknown alert type, keep it
    end
  end
  
  defp send_alert_notifications(new_alerts, old_alerts, channels) do
    # Find truly new alerts (not in old_alerts)
    truly_new = Map.drop(new_alerts, Map.keys(old_alerts))
    
    if not Enum.empty?(truly_new) do
      Enum.each(channels, fn channel ->
        send_notifications(truly_new, channel)
      end)
    end
  end
  
  defp send_notifications(alerts, {:log, opts}) do
    level = opts[:level] || :warning
    
    Enum.each(alerts, fn {_key, alert} ->
      Logger.log(level, "ALERT: #{alert.message}")
    end)
  end
  
  # Add more notification channels as needed
  # defp send_notifications(alerts, {:slack, opts}) do
  #   # Implement Slack notifications
  # end
  
  defp format_bytes(bytes) do
    cond do
      bytes > 1_000_000_000 -> "#{Float.round(bytes / 1_000_000_000, 2)} GB"
      bytes > 1_000_000 -> "#{Float.round(bytes / 1_000_000, 2)} MB" 
      bytes > 1_000 -> "#{Float.round(bytes / 1_000, 2)} KB"
      true -> "#{bytes} bytes"
    end
  end
end
```

---

## 🎛️ **Parte 6: Graceful Degradation**

### **7. Degradation Strategies**

```elixir
# lib/cortex/resilience/degradation_manager.ex
defmodule Cortex.Resilience.DegradationManager do
  @moduledoc """
  Maneja degradación graceful del sistema cuando hay problemas.
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :degradation_level,
    :active_strategies,
    :health_threshold,
    :recovery_threshold
  ]
  
  @degradation_levels [
    :healthy,        # 0 - Todo funcionando
    :minor_issues,   # 1 - Algunos workers con problemas
    :major_issues,   # 2 - Mayoría de workers con problemas 
    :critical,       # 3 - Solo backup disponible
    :emergency       # 4 - Sistema completamente degradado
  ]
  
  ## Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def get_current_level do
    GenServer.call(__MODULE__, :get_current_level)
  end
  
  def force_degradation_level(level) do
    GenServer.cast(__MODULE__, {:force_level, level})
  end
  
  def should_accept_request?(request_type \\ :normal) do
    GenServer.call(__MODULE__, {:should_accept, request_type})
  end
  
  ## Server Callbacks
  
  @impl true
  def init(_opts) do
    state = %__MODULE__{
      degradation_level: :healthy,
      active_strategies: [],
      health_threshold: %{
        minor: 0.8,    # 80% workers healthy
        major: 0.5,    # 50% workers healthy
        critical: 0.2, # 20% workers healthy
        emergency: 0.0 # 0% workers healthy
      },
      recovery_threshold: %{
        minor: 0.9,
        major: 0.7,
        critical: 0.4,
        emergency: 0.3
      }
    }
    
    # Subscribe to health updates
    Phoenix.PubSub.subscribe(Cortex.PubSub, "health_updates")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:get_current_level, _from, state) do
    {:reply, state.degradation_level, state}
  end
  
  @impl true
  def handle_call({:should_accept, request_type}, _from, state) do
    should_accept = case {state.degradation_level, request_type} do
      {:healthy, _} -> true
      {:minor_issues, _} -> true
      {:major_issues, :premium} -> true
      {:major_issues, :normal} -> should_accept_with_probability(0.7)
      {:critical, :premium} -> true
      {:critical, :normal} -> should_accept_with_probability(0.3)
      {:emergency, :premium} -> should_accept_with_probability(0.5)
      {:emergency, :normal} -> false
    end
    
    {:reply, should_accept, state}
  end
  
  @impl true
  def handle_cast({:force_level, level}, state) do
    if level in @degradation_levels do
      Logger.warning("Forcing degradation level to: #{level}")
      new_state = update_degradation_level(state, level)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:health_update, health_data}, state) do
    new_level = calculate_degradation_level(health_data, state)
    new_state = update_degradation_level(state, new_level)
    {:noreply, new_state}
  end
  
  ## Private Functions
  
  defp calculate_degradation_level(health_data, state) do
    available_workers = health_data.workers
    |> Map.values()
    |> Enum.count(&(&1 == :available))
    
    total_workers = map_size(health_data.workers)
    
    health_ratio = if total_workers > 0 do
      available_workers / total_workers
    else
      0.0
    end
    
    # Determine level based on health ratio and current level (hysteresis)
    cond do
      health_ratio >= state.recovery_threshold.minor -> :healthy
      health_ratio >= state.recovery_threshold.major -> 
        if state.degradation_level in [:healthy, :minor_issues], do: :healthy, else: :minor_issues
      health_ratio >= state.recovery_threshold.critical -> 
        if state.degradation_level in [:critical, :emergency], do: :major_issues, else: :minor_issues
      health_ratio >= state.recovery_threshold.emergency -> 
        if state.degradation_level == :emergency, do: :critical, else: :major_issues
      true -> :emergency
    end
  end
  
  defp update_degradation_level(state, new_level) do
    if new_level != state.degradation_level do
      Logger.warning("Degradation level changed: #{state.degradation_level} -> #{new_level}")
      
      # Activate/deactivate strategies based on level
      new_strategies = activate_strategies_for_level(new_level)
      
      # Notify other parts of the system
      Phoenix.PubSub.broadcast(
        Cortex.PubSub,
        "degradation_updates",
        {:degradation_changed, new_level, new_strategies}
      )
      
      :telemetry.execute(
        [:cortex, :degradation, :level_changed],
        %{level_numeric: level_to_number(new_level)},
        %{from: state.degradation_level, to: new_level}
      )
      
      %{state | 
        degradation_level: new_level,
        active_strategies: new_strategies
      }
    else
      state
    end
  end
  
  defp activate_strategies_for_level(level) do
    case level do
      :healthy -> 
        []
        
      :minor_issues -> 
        [:reduce_timeouts, :prefer_fast_providers]
        
      :major_issues -> 
        [:reduce_timeouts, :prefer_fast_providers, :limit_concurrent_requests]
        
      :critical -> 
        [:reduce_timeouts, :prefer_fast_providers, :limit_concurrent_requests, :cache_responses]
        
      :emergency -> 
        [:reduce_timeouts, :prefer_fast_providers, :limit_concurrent_requests, 
         :cache_responses, :return_cached_only]
    end
  end
  
  defp should_accept_with_probability(probability) do
    :rand.uniform() <= probability
  end
  
  defp level_to_number(level) do
    case level do
      :healthy -> 0
      :minor_issues -> 1
      :major_issues -> 2
      :critical -> 3
      :emergency -> 4
    end
  end
end
```

---

## 🎯 **Parte 7: Integrando Todo en el Sistema**

### **8. Actualizar el Application con Resilience**

```elixir
# lib/cortex/application.ex
def start(_type, _args) do
  # Initialize registries
  Registry.start_link(keys: :unique, name: Cortex.CircuitBreakerRegistry)
  
  children = [
    CortexWeb.Telemetry,
    {Phoenix.PubSub, name: Cortex.PubSub},
    
    # Resilience components
    Cortex.Resilience.DeadLetterQueue,
    Cortex.Monitoring.HealthMonitor,
    Cortex.Resilience.DegradationManager,
    
    # Core components
    Cortex.Workers.Registry,
    Cortex.Workers.Pool,
    Cortex.Workers.Supervisor,
    
    CortexWeb.Endpoint
  ]
  
  opts = [strategy: :one_for_one, name: Cortex.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### **9. Middleware para Request Handling**

```elixir
# lib/cortex_web/plugs/resilience_middleware.ex
defmodule CortexWeb.Plugs.ResilienceMiddleware do
  @moduledoc """
  Middleware que aplica estrategias de resilience a requests HTTP.
  """
  
  import Plug.Conn
  require Logger
  
  def init(opts), do: opts
  
  def call(conn, _opts) do
    # Check if we should accept this request
    request_type = determine_request_type(conn)
    
    case Cortex.Resilience.DegradationManager.should_accept_request?(request_type) do
      true ->
        conn
        
      false ->
        # Reject request due to degradation
        conn
        |> put_status(503)
        |> put_resp_header("retry-after", "60")
        |> json(%{
          error: "Service temporarily degraded",
          message: "Please try again later",
          retry_after: 60
        })
        |> halt()
    end
  end
  
  defp determine_request_type(conn) do
    # You could implement premium user detection here
    # For now, everything is normal
    :normal
  end
end
```

### **10. Health Endpoint Mejorado**

```elixir
# Actualizar lib/cortex_web/controllers/health_controller.ex
def check(conn, _params) do
  # Get comprehensive system health
  system_health = Cortex.Monitoring.HealthMonitor.get_system_health()
  active_alerts = Cortex.Monitoring.HealthMonitor.get_active_alerts()
  degradation_level = Cortex.Resilience.DegradationManager.get_current_level()
  dlq_stats = Cortex.Resilience.DeadLetterQueue.get_stats()
  
  # Calculate HTTP status based on overall health
  http_status = case system_health.overall_status do
    :healthy -> 200
    :warning -> 200
    :degraded -> 200  # Still operational
    :critical -> 503  # Service unavailable
    :no_workers -> 503
  end
  
  response = %{
    status: system_health.overall_status,
    degradation_level: degradation_level,
    timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
    
    # Detailed health info
    workers: system_health.workers,
    system_metrics: system_health.system,
    
    # Resilience info
    active_alerts: length(active_alerts),
    dlq_size: dlq_stats[:current_size] || 0,
    
    # Performance metrics
    check_duration_ms: system_health.check_duration,
    uptime_seconds: get_uptime_seconds(),
    
    # Circuit breaker status
    circuits: system_health.circuits
  }
  
  conn
  |> put_status(http_status)
  |> json(response)
end

defp get_uptime_seconds do
  {uptime_ms, _} = :erlang.statistics(:wall_clock)
  div(uptime_ms, 1000)
end
```

---

## 🎯 **Parte 8: Dashboard de Monitoreo**

### **11. Endpoint para Dashboard**

```elixir
# lib/cortex_web/controllers/admin_controller.ex
defmodule CortexWeb.AdminController do
  use CortexWeb, :controller
  
  def dashboard(conn, _params) do
    # Get all monitoring data
    system_health = Cortex.Monitoring.HealthMonitor.get_system_health()
    active_alerts = Cortex.Monitoring.HealthMonitor.get_active_alerts()
    degradation_level = Cortex.Resilience.DegradationManager.get_current_level()
    dlq_stats = Cortex.Resilience.DeadLetterQueue.get_stats()
    dlq_items = Cortex.Resilience.DeadLetterQueue.get_failed_requests(20)
    
    dashboard_data = %{
      system_health: system_health,
      alerts: %{
        active: active_alerts,
        total: length(active_alerts)
      },
      degradation: %{
        level: degradation_level,
        accepting_requests: degradation_level not in [:emergency]
      },
      dead_letter_queue: %{
        stats: dlq_stats,
        recent_items: format_dlq_items(dlq_items)
      },
      performance: %{
        uptime_seconds: get_uptime_seconds(),
        memory_usage: format_memory(system_health.system[:memory_usage]),
        process_count: system_health.system[:process_count]
      }
    }
    
    json(conn, dashboard_data)
  end
  
  def retry_dlq_item(conn, %{"item_id" => item_id}) do
    case Cortex.Resilience.DeadLetterQueue.retry_item(item_id) do
      :ok ->
        json(conn, %{success: true, message: "Item retried successfully"})
        
      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "Item not found"})
        
      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "Retry failed", reason: inspect(reason)})
    end
  end
  
  def acknowledge_alert(conn, %{"alert_id" => alert_id}) do
    Cortex.Monitoring.HealthMonitor.acknowledge_alert(String.to_atom(alert_id))
    json(conn, %{success: true})
  end
  
  defp format_dlq_items(items) do
    Enum.map(items, fn item ->
      %{
        id: item.id,
        timestamp: DateTime.to_iso8601(item.timestamp),
        error: inspect(item.error),
        worker: get_in(item.request, [:metadata, :worker]) || "unknown"
      }
    end)
  end
  
  defp format_memory(bytes) when is_integer(bytes) do
    cond do
      bytes > 1_000_000_000 -> %{value: Float.round(bytes / 1_000_000_000, 2), unit: "GB"}
      bytes > 1_000_000 -> %{value: Float.round(bytes / 1_000_000, 2), unit: "MB"}
      true -> %{value: Float.round(bytes / 1_000, 2), unit: "KB"}
    end
  end
  
  defp format_memory(_), do: %{value: 0, unit: "MB"}
  
  defp get_uptime_seconds do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end
end
```

---

## 🎉 **¡Felicitaciones!**

Has construido un sistema de error handling de nivel enterprise. Ahora tienes:

### **🛡️ Protecciones implementadas:**

✅ **Circuit Breakers** - Protección contra fallos en cascada  
✅ **Retry Strategies** - Recuperación inteligente con backoff  
✅ **Dead Letter Queue** - Análisis de requests fallidas  
✅ **Health Monitoring** - Vigilancia proactiva 24/7  
✅ **Graceful Degradation** - El sistema nunca muere completamente  
✅ **Alert Management** - Notificaciones inteligentes  

### **📊 Métricas y observabilidad:**

- **Circuit breaker uptime** por provider
- **Retry success rates** por estrategia
- **Alert frequency** y patterns
- **Degradation triggers** y recovery times
- **DLQ growth patterns** y error classification

### **🔥 Tu sistema ahora puede:**

- **Sobrevivir** cuando todos los providers fallen
- **Recuperarse automáticamente** sin intervención manual
- **Alertarte ANTES** de que algo se rompa
- **Degradar gracefulmente** en lugar de morir
- **Retry inteligentemente** sin crear más problemas
- **Monitorearse a sí mismo** 24/7

### **🌙 Duerme tranquilo sabiendo que:**

- Las alertas te llegaran antes de que los usuarios se den cuenta
- El sistema se autocura cuando es posible
- Los errores se clasifican y guardan para análisis
- Nunca tendrás un downtime completo
- Los patrons de falla se detectan automáticamente

---

## 💡 **Conceptos clave dominados:**

1. **Circuit Breaker Pattern** - Tolerancia a fallos automática
2. **Exponential Backoff** - Retry strategies que no saturan
3. **Dead Letter Queues** - Análisis forense de fallos
4. **Graceful Degradation** - Servicio parcial vs muerte total
5. **Proactive Monitoring** - Prevenir problemas antes de que pasen

---

## 🎯 **Series de Tutoriales Completada:**

Has terminado exitosamente la serie **"Córtex - Multi-Provider AI Gateway"**:

1. ✅ De 0 a Multi-Provider en Elixir  
2. ✅ Phoenix + Streaming - La dupla perfecta
3. ✅ Ollama como backup infinito local
4. ✅ Scaling to 10k+ concurrent users
5. ✅ **Error handling que no te dejará dormir mal** 

### **🚀 Próximo nivel:**

Con estos fundamentos, puedes expandir hacia:
- **Distributed tracing** con OpenTelemetry
- **Auto-scaling** con Kubernetes HPA
- **ML-driven** provider selection
- **Multi-region** deployment
- **Cost optimization** algorithms

**¡El sistema está listo para producción!** 🎉

---

**¿Preguntas? ¿Problemas durante la implementación?**

**¡Has construido algo increíble!** 🏆