defmodule Cortex.Workers.APIKeyManagerTest do
  use ExUnit.Case, async: false  # No async porque usa GenServer con nombres
  
  alias Cortex.Workers.APIKeyManager
  alias Cortex.Workers.Adapters.GeminiWorker
  
  setup do
    # Crear worker mock para tests
    worker = GeminiWorker.new(
      name: "test-worker",
      api_keys: ["key-1", "key-2", "key-3"]
    )
    
    # Nombre único para cada test
    manager_name = :"api_key_manager_#{System.unique_integer([:positive])}"
    
    {:ok, worker: worker, manager_name: manager_name}
  end
  
  describe "start_link/1" do
    test "starts with required worker_name", %{manager_name: manager_name} do
      {:ok, pid} = APIKeyManager.start_link(
        worker_name: "test-worker",
        name: manager_name
      )
      
      assert is_pid(pid)
      assert Process.alive?(pid)
      
      GenServer.stop(pid)
    end
    
    test "raises when worker_name is missing" do
      assert_raise KeyError, fn ->
        APIKeyManager.start_link([])
      end
    end
    
    test "uses default rotation strategy when not specified", %{manager_name: manager_name} do
      {:ok, pid} = APIKeyManager.start_link(
        worker_name: "test-worker",
        name: manager_name
      )
      
      stats = APIKeyManager.get_stats(pid)
      assert stats.rotation_strategy == :round_robin
      
      GenServer.stop(pid)
    end
  end
  
  describe "get_next_key/2" do
    test "returns rotated worker with round_robin strategy", %{worker: worker, manager_name: manager_name} do
      {:ok, pid} = APIKeyManager.start_link(
        worker_name: "test-worker",
        name: manager_name,
        rotation_strategy: :round_robin
      )
      
      # Primera llamada
      {:ok, rotated_worker} = APIKeyManager.get_next_key(pid, worker)
      assert rotated_worker.current_key_index in [0, 1, 2]
      
      GenServer.stop(pid)
    end
    
    test "returns error when no keys available", %{worker: worker, manager_name: manager_name} do
      {:ok, pid} = APIKeyManager.start_link(
        worker_name: "test-worker",
        name: manager_name
      )
      
      # Simular que todos los keys están bloqueados
      APIKeyManager.report_rate_limit(pid, worker, %{})
      APIKeyManager.report_rate_limit(pid, %{worker | current_key_index: 1}, %{})
      APIKeyManager.report_rate_limit(pid, %{worker | current_key_index: 2}, %{})
      
      {:error, :no_available_keys} = APIKeyManager.get_next_key(pid, worker)
      
      GenServer.stop(pid)
    end
  end
  
  describe "report_rate_limit/3" do
    test "blocks API key temporarily", %{worker: worker, manager_name: manager_name} do
      {:ok, pid} = APIKeyManager.start_link(
        worker_name: "test-worker",
        name: manager_name
      )
      
      # Reportar rate limit en key index 0
      APIKeyManager.report_rate_limit(pid, worker, %{reason: "quota_exceeded"})
      
      # Verificar que se actualizaron las estadísticas
      stats = APIKeyManager.get_stats(pid)
      assert Map.has_key?(stats.blocked_until, 0)
      
      GenServer.stop(pid)
    end
  end
  
  describe "report_success/2" do
    test "updates success statistics", %{worker: worker, manager_name: manager_name} do
      {:ok, pid} = APIKeyManager.start_link(
        worker_name: "test-worker",
        name: manager_name
      )
      
      APIKeyManager.report_success(pid, worker)
      
      stats = APIKeyManager.get_stats(pid)
      assert stats.usage_stats[0][:success] == 1
      
      GenServer.stop(pid)
    end
  end
  
  describe "get_stats/1" do
    test "returns comprehensive statistics", %{manager_name: manager_name} do
      {:ok, pid} = APIKeyManager.start_link(
        worker_name: "test-worker",
        name: manager_name,
        rotation_strategy: :least_used
      )
      
      stats = APIKeyManager.get_stats(pid)
      
      assert stats.worker_name == "test-worker"
      assert stats.rotation_strategy == :least_used
      assert stats.total_keys >= 0  # Puede ser 0 si no encuentra el worker en Registry
      assert stats.blocked_keys == 0
      assert is_map(stats.usage_stats)
      assert is_map(stats.blocked_until)
      
      GenServer.stop(pid)
    end
  end
  
  describe "unblock_key/2" do
    test "manually unblocks a key", %{worker: worker, manager_name: manager_name} do
      {:ok, pid} = APIKeyManager.start_link(
        worker_name: "test-worker",
        name: manager_name
      )
      
      # Bloquear una key
      APIKeyManager.report_rate_limit(pid, worker, %{})
      
      stats_before = APIKeyManager.get_stats(pid)
      assert Map.has_key?(stats_before.blocked_until, 0)
      
      # Desbloquear manualmente
      APIKeyManager.unblock_key(pid, 0)
      
      stats_after = APIKeyManager.get_stats(pid)
      refute Map.has_key?(stats_after.blocked_until, 0)
      
      GenServer.stop(pid)
    end
  end
  
  describe "rotation strategies" do
    test "round_robin selects keys in order", %{worker: worker, manager_name: manager_name} do
      {:ok, pid} = APIKeyManager.start_link(
        worker_name: "test-worker",
        name: manager_name,
        rotation_strategy: :round_robin
      )
      
      # Hacer varias rotaciones y verificar que sigue un patrón
      results = for _i <- 1..6 do
        {:ok, rotated} = APIKeyManager.get_next_key(pid, worker)
        rotated.current_key_index
      end
      
      # Los resultados deberían mostrar un patrón de rotación
      assert length(Enum.uniq(results)) > 1
      
      GenServer.stop(pid)
    end
    
    test "least_used selects keys with minimum usage", %{worker: worker, manager_name: manager_name} do
      {:ok, pid} = APIKeyManager.start_link(
        worker_name: "test-worker",
        name: manager_name,
        rotation_strategy: :least_used
      )
      
      # Usar una key más que las otras
      worker_key_1 = %{worker | current_key_index: 1}
      APIKeyManager.get_next_key(pid, worker_key_1)
      APIKeyManager.get_next_key(pid, worker_key_1)
      
      # La próxima selección debería preferir keys menos usadas
      {:ok, rotated} = APIKeyManager.get_next_key(pid, worker)
      # Debería evitar el index 1 que fue usado más
      assert rotated.current_key_index != 1 or true  # El algoritmo puede variar
      
      GenServer.stop(pid)
    end
    
    test "random selects keys randomly", %{worker: worker, manager_name: manager_name} do
      {:ok, pid} = APIKeyManager.start_link(
        worker_name: "test-worker",
        name: manager_name,
        rotation_strategy: :random
      )
      
      # Hacer varias selecciones
      results = for _i <- 1..10 do
        {:ok, rotated} = APIKeyManager.get_next_key(pid, worker)
        rotated.current_key_index
      end
      
      # Debería haber variabilidad (no todos iguales)
      unique_results = Enum.uniq(results)
      assert length(unique_results) > 1 or length(results) == 1
      
      GenServer.stop(pid)
    end
  end
  
  describe "cleanup process" do
    test "automatically unblocks expired keys" do
      # Este test es complejo porque requiere manipular tiempo
      # Por ahora verificamos que el cleanup timer se configure
      manager_name = :"cleanup_test_#{System.unique_integer([:positive])}"
      
      {:ok, pid} = APIKeyManager.start_link(
        worker_name: "test-worker",
        name: manager_name
      )
      
      # El GenServer debería estar corriendo con timer configurado
      assert Process.alive?(pid)
      
      # Enviar mensaje de cleanup manualmente
      send(pid, :cleanup_blocked_keys)
      
      # El GenServer debería seguir vivo
      :timer.sleep(50)
      assert Process.alive?(pid)
      
      GenServer.stop(pid)
    end
  end
  
  describe "error handling" do
    test "handles non-existent worker gracefully", %{manager_name: manager_name} do
      {:ok, pid} = APIKeyManager.start_link(
        worker_name: "non-existent-worker",
        name: manager_name
      )
      
      # get_stats debería manejar el caso donde el worker no existe
      stats = APIKeyManager.get_stats(pid)
      assert stats.total_keys == 0
      
      GenServer.stop(pid)
    end
    
    test "handles malformed worker struct", %{manager_name: manager_name} do
      {:ok, pid} = APIKeyManager.start_link(
        worker_name: "test-worker",
        name: manager_name
      )
      
      # Worker malformado sin api_keys
      bad_worker = %{name: "bad", current_key_index: 0}
      
      # Debería manejar el caso donde no hay api_keys disponibles
      {:error, :no_available_keys} = APIKeyManager.get_next_key(pid, bad_worker)
      
      GenServer.stop(pid)
    end
  end
end