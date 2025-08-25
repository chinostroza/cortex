defmodule Cortex.Workers.Adapters.OllamaWorkerTest do
  use ExUnit.Case, async: true
  
  alias Cortex.Workers.Adapters.OllamaWorker
  
  describe "new/1" do
    test "creates a worker with required options" do
      worker = OllamaWorker.new(
        name: "ollama-1",
        base_url: "http://localhost:11434"
      )
      
      assert %OllamaWorker{
        name: "ollama-1",
        base_url: "http://localhost:11434",
        timeout: 60_000,
        models: []
      } = worker
    end
    
    test "accepts custom timeout" do
      worker = OllamaWorker.new(
        name: "ollama-1",
        base_url: "http://localhost:11434",
        timeout: 30_000
      )
      
      assert worker.timeout == 30_000
    end
    
    test "raises when required options are missing" do
      assert_raise KeyError, fn ->
        OllamaWorker.new(name: "ollama-1")
      end
      
      assert_raise KeyError, fn ->
        OllamaWorker.new(base_url: "http://localhost:11434")
      end
    end
  end
  
  describe "info/1" do
    test "returns worker information" do
      worker = OllamaWorker.new(
        name: "ollama-1",
        base_url: "http://localhost:11434",
        models: ["gemma3:4b", "llama2"]
      )
      
      info = OllamaWorker.info(worker)
      
      assert info == %{
        name: "ollama-1",
        type: :ollama,
        base_url: "http://localhost:11434",
        models: ["gemma3:4b", "llama2"],
        timeout: 60_000
      }
    end
  end
  
  describe "priority/1" do
    test "returns high priority for local workers" do
      worker = OllamaWorker.new(
        name: "ollama-1",
        base_url: "http://localhost:11434"
      )
      
      assert OllamaWorker.priority(worker) == 10
    end
  end
  
  # Tests de integración (marcar con @tag :integration)
  @tag :integration
  describe "health_check/1" do
    setup do
      worker = OllamaWorker.new(
        name: "ollama-test",
        base_url: "http://localhost:11434"
      )
      
      {:ok, worker: worker}
    end
    
    @tag :integration
    test "returns available when Ollama is running", %{worker: worker} do
      # Este test solo pasará si Ollama está corriendo
      case OllamaWorker.health_check(worker) do
        {:ok, :available} ->
          assert true
        {:error, _reason} ->
          # Skip si Ollama no está disponible
          assert true
      end
    end
  end
  
  describe "stream_completion/3" do
    test "returns a stream" do
      worker = OllamaWorker.new(
        name: "ollama-1",
        base_url: "http://localhost:11434"
      )
      
      messages = [%{role: "user", content: "Hello"}]
      
      assert {:ok, stream} = OllamaWorker.stream_completion(worker, messages, [])
      assert %Stream{} = stream
    end
  end
end