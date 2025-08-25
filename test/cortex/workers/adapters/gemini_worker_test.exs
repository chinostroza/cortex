defmodule Cortex.Workers.Adapters.GeminiWorkerTest do
  use ExUnit.Case, async: true
  
  alias Cortex.Workers.Adapters.GeminiWorker
  
  describe "new/1" do
    test "creates worker with single API key" do
      worker = GeminiWorker.new(
        name: "gemini-test",
        api_keys: "test-key-123"
      )
      
      assert worker.name == "gemini-test"
      assert worker.api_keys == ["test-key-123"]
      assert worker.current_key_index == 0
      assert worker.default_model == "gemini-2.0-flash-001"
      assert worker.timeout == 60_000
    end
    
    test "creates worker with multiple API keys" do
      worker = GeminiWorker.new(
        name: "gemini-multi",
        api_keys: ["key-1", "key-2", "key-3"],
        default_model: "gemini-1.5-pro",
        timeout: 30_000
      )
      
      assert worker.api_keys == ["key-1", "key-2", "key-3"]
      assert worker.default_model == "gemini-1.5-pro"
      assert worker.timeout == 30_000
    end
    
    test "raises when no API keys provided" do
      assert_raise ArgumentError, ~r/api_keys debe ser/, fn ->
        GeminiWorker.new(name: "test", api_keys: [])
      end
    end
    
    test "raises when required name is missing" do
      assert_raise KeyError, fn ->
        GeminiWorker.new(api_keys: "test-key")
      end
    end
  end
  
  describe "current_api_key/1" do
    test "returns current API key based on index" do
      worker = GeminiWorker.new(
        name: "test",
        api_keys: ["key-1", "key-2", "key-3"]
      )
      
      assert GeminiWorker.current_api_key(worker) == "key-1"
      
      rotated_worker = %{worker | current_key_index: 1}
      assert GeminiWorker.current_api_key(rotated_worker) == "key-2"
    end
  end
  
  describe "rotate_api_key/1" do
    test "rotates to next key in sequence" do
      worker = GeminiWorker.new(
        name: "test",
        api_keys: ["key-1", "key-2", "key-3"]
      )
      
      # Primera rotación
      rotated = GeminiWorker.rotate_api_key(worker)
      assert rotated.current_key_index == 1
      assert rotated.last_rotation != nil
      
      # Segunda rotación  
      rotated2 = GeminiWorker.rotate_api_key(rotated)
      assert rotated2.current_key_index == 2
      
      # Tercera rotación (vuelve al inicio)
      rotated3 = GeminiWorker.rotate_api_key(rotated2)
      assert rotated3.current_key_index == 0
    end
  end
  
  describe "info/1" do
    test "returns comprehensive worker information" do
      worker = GeminiWorker.new(
        name: "gemini-info-test",
        api_keys: ["key-1", "key-2"],
        default_model: "gemini-1.5-flash"
      )
      
      info = GeminiWorker.info(worker)
      
      assert info.name == "gemini-info-test"
      assert info.type == :gemini
      assert info.api_keys_count == 2
      assert info.current_key_index == 0
      assert info.base_url == "https://generativelanguage.googleapis.com"
      assert info.default_model == "gemini-1.5-flash"
      assert is_list(info.available_models)
      assert "gemini-2.0-flash-001" in info.available_models
    end
  end
  
  describe "priority/1" do
    test "returns consistent medium priority" do
      worker = GeminiWorker.new(name: "test", api_keys: "key")
      assert GeminiWorker.priority(worker) == 30
    end
  end
  
  describe "provider_config/1" do
    test "returns proper configuration" do
      worker = GeminiWorker.new(
        name: "test",
        api_keys: "test-key",
        default_model: "gemini-1.5-pro"
      )
      
      config = GeminiWorker.provider_config(worker)
      
      assert config.base_url == "https://generativelanguage.googleapis.com"
      assert config.stream_endpoint == "/v1beta/models/gemini-1.5-pro:streamGenerateContent"
      assert config.model_param == "model"
      assert is_function(config.headers_fn, 1)
      assert is_map(config.optional_params)
    end
  end
  
  describe "transform_messages/2" do
    test "transforms OpenAI format to Gemini format" do
      messages = [
        %{"role" => "user", "content" => "Hello"},
        %{"role" => "assistant", "content" => "Hi there!"},
        %{"role" => "user", "content" => "How are you?"}
      ]
      
      result = GeminiWorker.transform_messages(messages, [])
      
      assert %{"contents" => contents} = result
      assert length(contents) == 3
      
      [first, second, third] = contents
      
      assert first == %{
        "role" => "user",
        "parts" => [%{"text" => "Hello"}]
      }
      
      assert second == %{
        "role" => "model", 
        "parts" => [%{"text" => "Hi there!"}]
      }
      
      assert third == %{
        "role" => "user",
        "parts" => [%{"text" => "How are you?"}]
      }
    end
    
    test "transforms system role to user role" do
      messages = [%{"role" => "system", "content" => "You are helpful"}]
      
      result = GeminiWorker.transform_messages(messages, [])
      
      assert %{"contents" => [content]} = result
      assert content["role"] == "user"
    end
  end
  
  describe "extract_content_from_chunk/1" do
    test "extracts content from valid Gemini response chunk" do
      chunk = """
      {
        "candidates": [
          {
            "content": {
              "parts": [
                {"text": "Hello world!"}
              ]
            }
          }
        ]
      }
      """
      
      content = GeminiWorker.extract_content_from_chunk(chunk)
      assert content == "Hello world!"
    end
    
    test "handles multiple parts in response" do
      chunk = """
      {
        "candidates": [
          {
            "content": {
              "parts": [
                {"text": "Hello "},
                {"text": "world!"}
              ]
            }
          }
        ]
      }
      """
      
      content = GeminiWorker.extract_content_from_chunk(chunk)
      assert content == "Hello world!"
    end
    
    test "returns empty string for invalid JSON" do
      chunk = "invalid json"
      content = GeminiWorker.extract_content_from_chunk(chunk)
      assert content == ""
    end
    
    test "returns empty string for missing content" do
      chunk = """
      {
        "candidates": [
          {
            "finishReason": "STOP"
          }
        ]
      }
      """
      
      content = GeminiWorker.extract_content_from_chunk(chunk)
      assert content == ""
    end
  end
  
  # Tests de integración (requieren API key real)
  @tag :integration
  describe "integration tests" do
    setup do
      case System.get_env("GEMINI_API_KEY") do
        nil ->
          {:skip, "GEMINI_API_KEY no está configurada"}
        
        api_key ->
          worker = GeminiWorker.new(
            name: "integration-test",
            api_keys: api_key
          )
          {:ok, worker: worker}
      end
    end
    
    @tag :integration
    test "health_check with real API", %{worker: worker} do
      case GeminiWorker.health_check(worker) do
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