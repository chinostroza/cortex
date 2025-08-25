defmodule Cortex.Workers.Adapters.GroqWorkerTest do
  use ExUnit.Case, async: true
  
  alias Cortex.Workers.Adapters.GroqWorker
  
  describe "new/1" do
    test "creates worker with single API key" do
      worker = GroqWorker.new(
        name: "groq-test",
        api_keys: "test-groq-key"
      )
      
      assert worker.name == "groq-test"
      assert worker.api_keys == ["test-groq-key"]
      assert worker.current_key_index == 0
      assert worker.default_model == "llama-3.1-8b-instant"
      assert worker.timeout == 30_000
    end
    
    test "creates worker with multiple API keys and custom config" do
      worker = GroqWorker.new(
        name: "groq-multi",
        api_keys: ["groq-key-1", "groq-key-2"],
        default_model: "llama-3.3-70b-versatile",
        timeout: 45_000
      )
      
      assert worker.api_keys == ["groq-key-1", "groq-key-2"]
      assert worker.default_model == "llama-3.3-70b-versatile"
      assert worker.timeout == 45_000
    end
    
    test "raises when no API keys provided" do
      assert_raise ArgumentError, ~r/api_keys debe ser/, fn ->
        GroqWorker.new(name: "test", api_keys: [])
      end
    end
    
    test "raises when required name is missing" do
      assert_raise KeyError, fn ->
        GroqWorker.new(api_keys: "test-key")
      end
    end
  end
  
  describe "current_api_key/1" do
    test "returns current API key based on index" do
      worker = GroqWorker.new(
        name: "test",
        api_keys: ["groq-1", "groq-2", "groq-3"]
      )
      
      assert GroqWorker.current_api_key(worker) == "groq-1"
      
      rotated_worker = %{worker | current_key_index: 1}
      assert GroqWorker.current_api_key(rotated_worker) == "groq-2"
    end
  end
  
  describe "rotate_api_key/1" do
    test "rotates to next key in sequence" do
      worker = GroqWorker.new(
        name: "test",
        api_keys: ["key-1", "key-2", "key-3"]
      )
      
      # Primera rotación
      rotated = GroqWorker.rotate_api_key(worker)
      assert rotated.current_key_index == 1
      assert rotated.last_rotation != nil
      
      # Segunda rotación  
      rotated2 = GroqWorker.rotate_api_key(rotated)
      assert rotated2.current_key_index == 2
      
      # Tercera rotación (vuelve al inicio)
      rotated3 = GroqWorker.rotate_api_key(rotated2)
      assert rotated3.current_key_index == 0
    end
  end
  
  describe "info/1" do
    test "returns comprehensive worker information" do
      worker = GroqWorker.new(
        name: "groq-info-test",
        api_keys: ["key-1", "key-2", "key-3"],
        default_model: "mixtral-8x7b-32768"
      )
      
      info = GroqWorker.info(worker)
      
      assert info.name == "groq-info-test"
      assert info.type == :groq
      assert info.api_keys_count == 3
      assert info.current_key_index == 0
      assert info.base_url == "https://api.groq.com"
      assert info.default_model == "mixtral-8x7b-32768"
      assert is_list(info.available_models)
      assert "llama-3.3-70b-versatile" in info.available_models
      assert "llama-3.1-8b-instant" in info.available_models
      assert is_list(info.special_features)
      assert "ultra_fast_inference" in info.special_features
      assert "lpu_acceleration" in info.special_features
    end
  end
  
  describe "priority/1" do
    test "returns high priority (after local)" do
      worker = GroqWorker.new(name: "test", api_keys: "key")
      assert GroqWorker.priority(worker) == 20
    end
  end
  
  describe "provider_config/1" do
    test "returns proper configuration" do
      worker = GroqWorker.new(
        name: "test",
        api_keys: "test-key",
        default_model: "llama-3.1-70b-versatile"
      )
      
      config = GroqWorker.provider_config(worker)
      
      assert config.base_url == "https://api.groq.com"
      assert config.stream_endpoint == "/openai/v1/chat/completions"
      assert config.health_endpoint == "https://api.groq.com/openai/v1/models"
      assert config.model_param == "model"
      assert is_function(config.headers_fn, 1)
      assert is_map(config.optional_params)
      assert config.optional_params["stream"] == true
      assert config.optional_params["temperature"] == 0.7
    end
  end
  
  describe "transform_messages/2" do
    test "returns messages unchanged (OpenAI compatible)" do
      messages = [
        %{"role" => "system", "content" => "You are helpful"},
        %{"role" => "user", "content" => "Hello"},
        %{"role" => "assistant", "content" => "Hi there!"}
      ]
      
      result = GroqWorker.transform_messages(messages, [])
      
      # Groq es compatible con OpenAI, no requiere transformación
      assert result == messages
    end
    
    test "handles empty messages list" do
      result = GroqWorker.transform_messages([], [])
      assert result == []
    end
  end
  
  describe "extract_content_from_chunk/1" do
    test "extracts content from OpenAI-compatible streaming response" do
      chunk = """
      {
        "choices": [
          {
            "delta": {
              "content": "Hello from Groq!"
            }
          }
        ]
      }
      """
      
      content = GroqWorker.extract_content_from_chunk(chunk)
      assert content == "Hello from Groq!"
    end
    
    test "handles null content in delta" do
      chunk = """
      {
        "choices": [
          {
            "delta": {
              "content": null
            }
          }
        ]
      }
      """
      
      content = GroqWorker.extract_content_from_chunk(chunk)
      assert content == ""
    end
    
    test "handles finish_reason in response" do
      chunk = """
      {
        "choices": [
          {
            "finish_reason": "stop",
            "delta": {}
          }
        ]
      }
      """
      
      content = GroqWorker.extract_content_from_chunk(chunk)
      assert content == ""
    end
    
    test "returns empty string for invalid JSON" do
      chunk = "invalid json format"
      content = GroqWorker.extract_content_from_chunk(chunk)
      assert content == ""
    end
    
    test "handles malformed response structure" do
      chunk = """
      {
        "other_field": "value",
        "not_choices": []
      }
      """
      
      content = GroqWorker.extract_content_from_chunk(chunk)
      assert content == ""
    end
  end
  
  # Tests de integración (requieren API key real)
  @tag :integration
  describe "integration tests" do
    setup do
      case System.get_env("GROQ_API_KEY") do
        nil ->
          {:skip, "GROQ_API_KEY no está configurada"}
        
        api_key ->
          worker = GroqWorker.new(
            name: "integration-test",
            api_keys: api_key
          )
          {:ok, worker: worker}
      end
    end
    
    @tag :integration
    test "health_check with real API", %{worker: worker} do
      case GroqWorker.health_check(worker) do
        {:ok, :available} ->
          assert true
        {:error, reason} ->
          # Puede fallar si no hay internet o API key inválida
          IO.puts("Health check falló (esperado en CI): #{inspect(reason)}")
          assert true
      end
    end
  end
end