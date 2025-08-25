defmodule Cortex.Workers.SupervisorTest do
  use ExUnit.Case, async: false  # async: false porque usa Application env
  
  alias Cortex.Workers.{Supervisor, Registry, Pool}
  
  setup do
    # Limpiar configuración antes de cada test
    original_config = Application.get_env(:cortex, :workers, [])
    Application.put_env(:cortex, :workers, [])
    
    on_exit(fn ->
      Application.put_env(:cortex, :workers, original_config)
    end)
    
    :ok
  end
  
  describe "start_link/1" do
    test "starts supervisor with default names" do
      {:ok, supervisor_pid} = Supervisor.start_link(name: TestSupervisor)
      
      # Verificar que los procesos hijos están corriendo
      children = DynamicSupervisor.which_children(supervisor_pid)
      assert length(children) > 0
      
      # Limpiar
      GenServer.stop(supervisor_pid)
    end
  end
  
  describe "add_worker/3" do
    setup do
      {:ok, supervisor_pid} = Supervisor.start_link(
        name: TestSupervisor,
        registry_name: TestRegistry,
        pool_name: TestPool
      )
      
      # Esperar a que se complete la configuración inicial
      Process.sleep(100)
      
      on_exit(fn ->
        GenServer.stop(supervisor_pid)
      end)
      
      {:ok, supervisor: supervisor_pid}
    end
    
    test "adds ollama worker successfully", %{supervisor: supervisor} do
      worker_opts = [
        type: :ollama,
        base_url: "http://localhost:11434",
        models: ["llama2"]
      ]
      
      assert :ok = Supervisor.add_worker(supervisor, "test-ollama", worker_opts)
      
      # Verificar que el worker fue registrado
      workers = Supervisor.list_workers(supervisor)
      assert length(workers) >= 1
      
      # Encontrar nuestro worker
      test_worker = Enum.find(workers, fn w -> w.name == "test-ollama" end)
      assert test_worker != nil
      assert test_worker.base_url == "http://localhost:11434"
    end
    
    test "returns error for unsupported worker type", %{supervisor: supervisor} do
      worker_opts = [type: :unsupported_type]
      
      assert {:error, :unsupported_worker_type} = 
        Supervisor.add_worker(supervisor, "invalid-worker", worker_opts)
    end
  end
  
  describe "remove_worker/2" do
    setup do
      {:ok, supervisor_pid} = Supervisor.start_link(
        name: TestSupervisor2,
        registry_name: TestRegistry2,
        pool_name: TestPool2
      )
      
      # Esperar a que se complete la configuración inicial
      Process.sleep(100)
      
      # Agregar un worker para remover
      worker_opts = [
        type: :ollama,
        base_url: "http://localhost:11434"
      ]
      Supervisor.add_worker(supervisor_pid, "removable-worker", worker_opts)
      
      on_exit(fn ->
        GenServer.stop(supervisor_pid)
      end)
      
      {:ok, supervisor: supervisor_pid}
    end
    
    test "removes worker successfully", %{supervisor: supervisor} do
      # Verificar que el worker existe
      workers_before = Supervisor.list_workers(supervisor)
      removable_worker = Enum.find(workers_before, fn w -> 
        w.name == "removable-worker" 
      end)
      assert removable_worker != nil
      
      # Remover el worker
      assert :ok = Supervisor.remove_worker(supervisor, "removable-worker")
      
      # Verificar que el worker ya no existe
      workers_after = Supervisor.list_workers(supervisor)
      removable_worker = Enum.find(workers_after, fn w -> 
        w.name == "removable-worker" 
      end)
      assert removable_worker == nil
    end
  end
  
  describe "configuration" do
    test "uses default worker when no configuration" do
      Application.put_env(:cortex, :workers, [])
      
      {:ok, supervisor_pid} = Supervisor.start_link(
        name: TestSupervisor3,
        registry_name: TestRegistry3,
        pool_name: TestPool3
      )
      
      # Esperar a que se complete la configuración
      Process.sleep(200)
      
      workers = Supervisor.list_workers(supervisor_pid)
      
      # Debe haber al menos el worker por defecto
      default_worker = Enum.find(workers, fn w -> w.name == "ollama-local" end)
      assert default_worker != nil
      assert default_worker.base_url == "http://localhost:11434"
      
      GenServer.stop(supervisor_pid)
    end
    
    test "uses custom configuration when provided" do
      custom_config = [
        %{
          name: "custom-ollama",
          type: :ollama,
          base_url: "http://custom:8080",
          models: ["custom-model"]
        }
      ]
      
      Application.put_env(:cortex, :workers, custom_config)
      
      {:ok, supervisor_pid} = Supervisor.start_link(
        name: TestSupervisor4,
        registry_name: TestRegistry4,
        pool_name: TestPool4
      )
      
      # Esperar a que se complete la configuración
      Process.sleep(200)
      
      workers = Supervisor.list_workers(supervisor_pid)
      
      custom_worker = Enum.find(workers, fn w -> w.name == "custom-ollama" end)
      assert custom_worker != nil
      assert custom_worker.base_url == "http://custom:8080"
      assert custom_worker.models == ["custom-model"]
      
      GenServer.stop(supervisor_pid)
    end
  end
end