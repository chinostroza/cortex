defmodule Cortex.Workers.RegistryTest do
  use ExUnit.Case, async: true
  
  alias Cortex.Workers.Registry
  alias Cortex.Workers.Adapters.OllamaWorker
  
  setup do
    # Iniciamos un registry único para cada test
    {:ok, registry} = Registry.start_link(name: nil)
    {:ok, registry: registry}
  end
  
  describe "register/3" do
    test "registers a new worker", %{registry: registry} do
      worker = OllamaWorker.new(
        name: "test-ollama",
        base_url: "http://localhost:11434"
      )
      
      assert :ok = Registry.register(registry, "test-ollama", worker)
    end
    
    test "returns error when registering duplicate name", %{registry: registry} do
      worker = OllamaWorker.new(
        name: "test-ollama",
        base_url: "http://localhost:11434"
      )
      
      assert :ok = Registry.register(registry, "test-ollama", worker)
      assert {:error, :already_registered} = Registry.register(registry, "test-ollama", worker)
    end
  end
  
  describe "unregister/2" do
    test "removes a registered worker", %{registry: registry} do
      worker = OllamaWorker.new(
        name: "test-ollama",
        base_url: "http://localhost:11434"
      )
      
      Registry.register(registry, "test-ollama", worker)
      assert :ok = Registry.unregister(registry, "test-ollama")
      assert {:error, :not_found} = Registry.get(registry, "test-ollama")
    end
    
    test "returns ok even if worker doesn't exist", %{registry: registry} do
      assert :ok = Registry.unregister(registry, "non-existent")
    end
  end
  
  describe "get/2" do
    test "retrieves a registered worker", %{registry: registry} do
      worker = OllamaWorker.new(
        name: "test-ollama",
        base_url: "http://localhost:11434"
      )
      
      Registry.register(registry, "test-ollama", worker)
      assert {:ok, ^worker} = Registry.get(registry, "test-ollama")
    end
    
    test "returns error for non-existent worker", %{registry: registry} do
      assert {:error, :not_found} = Registry.get(registry, "non-existent")
    end
  end
  
  describe "list_all/1" do
    test "returns empty list when no workers", %{registry: registry} do
      assert [] = Registry.list_all(registry)
    end
    
    test "returns all registered workers", %{registry: registry} do
      worker1 = OllamaWorker.new(
        name: "ollama-1",
        base_url: "http://localhost:11434"
      )
      
      worker2 = OllamaWorker.new(
        name: "ollama-2",
        base_url: "http://localhost:11435"
      )
      
      Registry.register(registry, "ollama-1", worker1)
      Registry.register(registry, "ollama-2", worker2)
      
      workers = Registry.list_all(registry)
      assert length(workers) == 2
      assert worker1 in workers
      assert worker2 in workers
    end
  end
  
  describe "list_by_type/2" do
    test "filters workers by type", %{registry: registry} do
      ollama_worker = OllamaWorker.new(
        name: "ollama-1",
        base_url: "http://localhost:11434"
      )
      
      Registry.register(registry, "ollama-1", ollama_worker)
      
      assert [^ollama_worker] = Registry.list_by_type(registry, :ollama)
      assert [] = Registry.list_by_type(registry, :gemini)
    end
  end
  
  describe "count/1" do
    test "returns number of registered workers", %{registry: registry} do
      assert 0 = Registry.count(registry)
      
      worker = OllamaWorker.new(
        name: "test-ollama",
        base_url: "http://localhost:11434"
      )
      
      Registry.register(registry, "test-ollama", worker)
      assert 1 = Registry.count(registry)
      
      Registry.unregister(registry, "test-ollama")
      assert 0 = Registry.count(registry)
    end
  end
end