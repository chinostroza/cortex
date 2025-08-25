defmodule Cortex.Workers.PoolTest do
  use ExUnit.Case, async: true
  
  alias Cortex.Workers.{Pool, Registry}
  alias Cortex.Workers.Adapters.OllamaWorker
  
  # Mock worker para tests
  defmodule MockWorker do
    @behaviour Cortex.Workers.Worker
    
    defstruct [:name, :should_fail, :priority_value]
    
    def new(opts) do
      %__MODULE__{
        name: Keyword.fetch!(opts, :name),
        should_fail: Keyword.get(opts, :should_fail, false),
        priority_value: Keyword.get(opts, :priority, 50)
      }
    end
    
    @impl true
    def health_check(%{should_fail: true}), do: {:error, :mock_error}
    def health_check(_), do: {:ok, :available}
    
    @impl true
    def stream_completion(%{should_fail: true}, _messages, _opts) do
      {:error, :mock_stream_error}
    end
    def stream_completion(%{name: name}, _messages, _opts) do
      # Crear un stream simple para testing
      stream = Stream.iterate(1, &(&1 + 1))
      |> Stream.map(fn n -> "#{name}-chunk-#{n}" end)
      |> Stream.take(3)
      
      {:ok, stream}
    end
    
    @impl true
    def info(worker) do
      %{
        name: worker.name,
        type: :mock,
        priority: worker.priority_value
      }
    end
    
    @impl true
    def priority(%{priority_value: p}), do: p
  end
  
  setup do
    # Crear registry y pool únicos para cada test
    {:ok, registry} = Registry.start_link(name: nil)
    {:ok, pool} = Pool.start_link(
      registry: registry,
      check_interval: 60_000  # Intervalo largo para evitar checks automáticos en tests
    )
    
    {:ok, registry: registry, pool: pool}
  end
  
  describe "stream_completion/3" do
    test "selects available worker and returns stream", %{registry: registry, pool: pool} do
      worker = MockWorker.new(name: "mock-1")
      Registry.register(registry, "mock-1", worker)
      
      # Forzar health check
      Pool.check_health(pool)
      Process.sleep(100)  # Dar tiempo para que se complete
      
      messages = [%{role: "user", content: "test"}]
      assert {:ok, stream} = Pool.stream_completion(pool, messages)
      
      # Verificar que el stream funciona
      chunks = Enum.to_list(stream)
      assert ["mock-1-chunk-1", "mock-1-chunk-2", "mock-1-chunk-3"] = chunks
    end
    
    test "returns error when no workers available", %{pool: pool} do
      messages = [%{role: "user", content: "test"}]
      assert {:error, :no_workers_available} = Pool.stream_completion(pool, messages)
    end
    
    test "fails over to next worker when first fails", %{registry: registry, pool: pool} do
      failing_worker = MockWorker.new(name: "failing", should_fail: true, priority: 10)
      working_worker = MockWorker.new(name: "working", priority: 20)
      
      Registry.register(registry, "failing", failing_worker)
      Registry.register(registry, "working", working_worker)
      
      # Forzar health check
      Pool.check_health(pool)
      Process.sleep(100)
      
      messages = [%{role: "user", content: "test"}]
      assert {:ok, stream} = Pool.stream_completion(pool, messages)
      
      # Verificar que usó el worker que funciona
      chunks = Enum.to_list(stream)
      assert ["working-chunk-1", "working-chunk-2", "working-chunk-3"] = chunks
    end
  end
  
  describe "health_status/1" do
    test "returns health status of all workers", %{registry: registry, pool: pool} do
      worker1 = MockWorker.new(name: "healthy")
      worker2 = MockWorker.new(name: "unhealthy", should_fail: true)
      
      Registry.register(registry, "healthy", worker1)
      Registry.register(registry, "unhealthy", worker2)
      
      # Forzar health check
      Pool.check_health(pool)
      Process.sleep(100)
      
      status = Pool.health_status(pool)
      assert status["healthy"] == :available
      assert status["unhealthy"] == :unavailable
    end
  end
  
  describe "strategy :local_first" do
    test "prioritizes workers with lower priority number", %{registry: registry, pool: pool} do
      # Worker con prioridad 50
      remote_worker = MockWorker.new(name: "remote", priority: 50)
      # Worker con prioridad 10 (mayor prioridad)
      local_worker = MockWorker.new(name: "local", priority: 10)
      
      Registry.register(registry, "remote", remote_worker)
      Registry.register(registry, "local", local_worker)
      
      # Forzar health check
      Pool.check_health(pool)
      Process.sleep(100)
      
      messages = [%{role: "user", content: "test"}]
      assert {:ok, stream} = Pool.stream_completion(pool, messages)
      
      # Verificar que usó el worker local (menor número = mayor prioridad)
      chunks = Enum.to_list(stream)
      assert ["local-chunk-1", "local-chunk-2", "local-chunk-3"] = chunks
    end
  end
end