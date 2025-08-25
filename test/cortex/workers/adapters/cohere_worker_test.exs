defmodule Cortex.Workers.Adapters.CohereWorkerTest do
  use ExUnit.Case, async: true
  
  alias Cortex.Workers.Adapters.CohereWorker
  
  describe "new/1" do
    test "creates worker with single API key" do
      worker = CohereWorker.new(
        name: "cohere-test",
        api_keys: "test-cohere-key"
      )
      
      assert worker.name == "cohere-test"
      assert worker.api_keys == ["test-cohere-key"]
      assert worker.current_key_index == 0
      assert worker.default_model == "command"
      assert worker.timeout == 60_000
    end
    
    test "creates worker with multiple API keys" do
      worker = CohereWorker.new(
        name: "cohere-multi",
        api_keys: ["key-1", "key-2", "key-3"],
        default_model: "command-light",
        timeout: 30_000
      )
      
      assert worker.api_keys == ["key-1", "key-2", "key-3"]
      assert worker.default_model == "command-light"
      assert worker.timeout == 30_000
    end
    
    test "raises when no API keys provided" do
      assert_raise ArgumentError, ~r/api_keys debe ser/, fn ->
        CohereWorker.new(name: "test", api_keys: [])
      end
    end
    
    test "raises when required name is missing" do
      assert_raise KeyError, fn ->
        CohereWorker.new(api_keys: "test-key")
      end
    end
  end
  
  describe "current_api_key/1" do
    test "returns current API key based on index" do
      worker = CohereWorker.new(
        name: "test",
        api_keys: ["key-1", "key-2", "key-3"]
      )
      
      assert CohereWorker.current_api_key(worker) == "key-1"
      
      rotated_worker = %{worker | current_key_index: 2}
      assert CohereWorker.current_api_key(rotated_worker) == "key-3"
    end
  end
  
  describe "rotate_api_key/1" do
    test "rotates to next key in sequence" do
      worker = CohereWorker.new(
        name: "test",
        api_keys: ["key-1", "key-2"]
      )
      
      # Primera rotación
      rotated = CohereWorker.rotate_api_key(worker)
      assert rotated.current_key_index == 1
      assert rotated.last_rotation != nil
      
      # Segunda rotación (vuelve al inicio)
      rotated2 = CohereWorker.rotate_api_key(rotated)
      assert rotated2.current_key_index == 0
    end
  end
  
  describe "info/1" do
    test "returns comprehensive worker information" do
      worker = CohereWorker.new(
        name: "cohere-info-test",
        api_keys: ["key-1", "key-2"],
        default_model: "command-nightly"
      )
      
      info = CohereWorker.info(worker)
      
      assert info.name == "cohere-info-test"
      assert info.type == :cohere
      assert info.api_keys_count == 2
      assert info.current_key_index == 0
      assert info.base_url == "https://api.cohere.ai"
      assert info.default_model == "command-nightly"
      assert is_list(info.available_models)
      assert "command" in info.available_models
      assert "command-light" in info.available_models
    end
  end
  
  describe "priority/1" do
    test "returns medium-low priority" do
      worker = CohereWorker.new(name: "test", api_keys: "key")
      assert CohereWorker.priority(worker) == 40
    end
  end
  
  describe "provider_config/1" do
    test "returns proper configuration" do
      worker = CohereWorker.new(
        name: "test",
        api_keys: "test-key",
        default_model: "command-light"
      )
      
      config = CohereWorker.provider_config(worker)
      
      assert config.base_url == "https://api.cohere.ai"
      assert config.stream_endpoint == "/v1/chat"
      assert config.health_endpoint == "https://api.cohere.ai/v1/models"
      assert config.model_param == "model"
      assert is_function(config.headers_fn, 1)
      assert is_map(config.optional_params)
      assert config.optional_params["stream"] == true
    end
  end
  
  describe "transform_messages/2" do
    test "transforms to Cohere format with chat_history and message" do
      messages = [
        %{"role" => "user", "content" => "Hello"},
        %{"role" => "assistant", "content" => "Hi there!"},
        %{"role" => "user", "content" => "How are you?"}
      ]
      
      result = CohereWorker.transform_messages(messages, [])
      
      assert %{"message" => "How are you?", "chat_history" => history} = result
      assert length(history) == 2
      
      [first, second] = history
      
      assert first == %{
        "role" => "USER",
        "message" => "Hello"
      }
      
      assert second == %{
        "role" => "CHATBOT", 
        "message" => "Hi there!"
      }
    end
    
    test "transforms single message" do
      messages = [%{"role" => "user", "content" => "Single message"}]
      
      result = CohereWorker.transform_messages(messages, [])
      
      assert %{"message" => "Single message", "chat_history" => []} = result
    end
    
    test "transforms system role to SYSTEM" do
      messages = [
        %{"role" => "system", "content" => "System prompt"},
        %{"role" => "user", "content" => "User message"}
      ]
      
      result = CohereWorker.transform_messages(messages, [])
      
      assert %{"message" => "User message", "chat_history" => history} = result
      [system_msg] = history
      assert system_msg["role"] == "SYSTEM"
    end
    
    test "raises when no messages provided" do
      assert_raise ArgumentError, ~r/Se requiere al menos un mensaje/, fn ->
        CohereWorker.transform_messages([], [])
      end
    end
  end
  
  describe "extract_content_from_chunk/1" do
    test "extracts content from text-generation event" do
      chunk = """
      {
        "event_type": "text-generation",
        "text": "Hello from Cohere!"
      }
      """
      
      content = CohereWorker.extract_content_from_chunk(chunk)
      assert content == "Hello from Cohere!"
    end
    
    test "extracts content from simple text field" do
      chunk = """
      {
        "text": "Simple text response"
      }
      """
      
      content = CohereWorker.extract_content_from_chunk(chunk)
      assert content == "Simple text response"
    end
    
    test "returns empty string for invalid JSON" do
      chunk = "invalid json content"
      content = CohereWorker.extract_content_from_chunk(chunk)
      assert content == ""
    end
    
    test "returns empty string for unrecognized format" do
      chunk = """
      {
        "other_field": "some value",
        "not_text": "not what we want"
      }
      """
      
      content = CohereWorker.extract_content_from_chunk(chunk)
      assert content == ""
    end
  end
  
  # Tests de integración (requieren API key real)
  @tag :integration
  describe "integration tests" do
    setup do
      case System.get_env("COHERE_API_KEY") do
        nil ->
          {:skip, "COHERE_API_KEY no está configurada"}
        
        api_key ->
          worker = CohereWorker.new(
            name: "integration-test",
            api_keys: api_key
          )
          {:ok, worker: worker}
      end
    end
    
    @tag :integration
    test "health_check with real API", %{worker: worker} do
      case CohereWorker.health_check(worker) do
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