defmodule LangChain.MCP.ErrorHandlerTest do
  use ExUnit.Case, async: true

  alias LangChain.MCP.ErrorHandler

  describe "handle_error/1" do
    test "handles Anubis.MCP protocol errors correctly" do
      error = %Anubis.MCP.Error{
        code: -32600,
        reason: :invalid_request,
        message: "Invalid request format"
      }

      assert {:error, "MCP protocol error (invalid_request): Invalid request format"} =
               ErrorHandler.handle_error(error)
    end

    test "handles MCP transport errors correctly" do
      # Simulating transport error struct that matches the pattern expected by ErrorHandler
      error = %{
        __struct__: Anubis.MCP.Error,
        code: -32000,
        reason: :connection_refused,
        message: "Connection refused"
      }

      assert {:error, "MCP transport error (connection_refused): Could not connect to server"} =
               ErrorHandler.handle_error(error)
    end

    test "handles binary errors" do
      assert {:error, "MCP error: connection timeout"} =
               ErrorHandler.handle_error("connection timeout")
    end

    test "handles atom errors" do
      assert {:error, "MCP error: timeout"} = ErrorHandler.handle_error(:timeout)
    end

    test "handles other term errors with inspect" do
      error_tuple = {:badarg, [{:erlang, :binary_to_integer, ["abc"], 0}]}

      result = ErrorHandler.handle_error(error_tuple)
      assert elem(result, 0) == :error
      assert String.contains?(elem(result, 1), "MCP error:")
    end

    test "formats different protocol errors correctly" do
      test_cases = [
        {%Anubis.MCP.Error{code: -32700, reason: :parse_error},
         "MCP protocol error (parse_error): Invalid JSON in request or response"},
        {%Anubis.MCP.Error{
           code: -32601,
           reason: :method_not_found,
           data: %{"method" => "test_method"}
         }, "MCP protocol error (method_not_found): Method 'test_method' not found"},
        {%Anubis.MCP.Error{code: -32602, reason: :invalid_params},
         "MCP protocol error (invalid_params): Invalid parameters provided"},
        {%Anubis.MCP.Error{code: -32800, reason: :internal_error},
         "MCP protocol error (internal_error): Server internal error"}
      ]

      for {error, expected_message} <- test_cases do
        assert {:error, ^expected_message} = ErrorHandler.handle_error(error)
      end
    end

    test "formats transport errors correctly" do
      transport_errors = [
        {%Anubis.MCP.Error{code: -32000, reason: :request_timeout},
         "MCP transport error (request_timeout): Request timed out"},
        {%Anubis.MCP.Error{code: -32001, reason: :send_failure},
         "MCP transport error (send_failure): Failed to send message"},
        {%Anubis.MCP.Error{code: -32002, reason: :connection_refused},
         "MCP transport error (connection_refused): Could not connect to server"},
        {%Anubis.MCP.Error{code: -32003, reason: :request_cancelled},
         "MCP transport error (request_cancelled): Request was cancelled"}
      ]

      for {error, expected_message} <- transport_errors do
        assert {:error, ^expected_message} = ErrorHandler.handle_error(error)
      end
    end

    test "handles unknown reason codes with code fallback" do
      error = %Anubis.MCP.Error{
        code: -999,
        reason: :unknown_reason,
        message: "Custom error"
      }

      assert {:error, "MCP error (unknown_reason, code: -999): Custom error"} =
               ErrorHandler.handle_error(error)
    end

    test "handles errors without custom message" do
      error = %Anubis.MCP.Error{
        code: -32600,
        reason: :invalid_request
      }

      assert {:error, "MCP protocol error (invalid_request): Invalid request format"} =
               ErrorHandler.handle_error(error)
    end
  end

  describe "handle_response_error/1" do
    test "extracts text content from domain errors correctly" do
      response = %{
        is_error: true,
        result: %{"content" => [%{"type" => "text", "text" => "Tool execution failed"}]}
      }

      assert {:error, "Tool execution failed: Tool execution failed"} =
               ErrorHandler.handle_response_error(response)
    end

    test "extracts error message from content field" do
      response = %{
        is_error: true,
        result: %{"content" => [%{"type" => "text", "text" => "Something went wrong"}]}
      }

      assert {:error, "Tool execution failed: Something went wrong"} =
               ErrorHandler.handle_response_error(response)
    end

    test "extracts error from dedicated error field" do
      response = %{
        is_error: true,
        result: %{"error" => %{"code" => 500, "message" => "Server error"}}
      }

      assert {:error, "Tool execution failed: %{\"code\" => 500, \"message\" => \"Server error\"}"} =
               ErrorHandler.handle_response_error(response)
    end

    test "extracts from message field when available" do
      response = %{
        is_error: true,
        result: %{"message" => "Custom error occurred"}
      }

      assert {:error, "Tool execution failed: Custom error occurred"} =
               ErrorHandler.handle_response_error(response)
    end

    test "handles content without text type gracefully" do
      response = %{
        is_error: true,
        result: %{"content" => [%{"type" => "image", "data" => "base64data"}]}
      }

      result = ErrorHandler.handle_response_error(response)
      assert elem(result, 0) == :error
      assert String.contains?(elem(result, 1), "Tool execution failed:")
    end

    test "handles unexpected response format" do
      response = %{
        is_error: true,
        result: %{"unexpected" => "structure"}
      }

      result = ErrorHandler.handle_response_error(response)
      assert elem(result, 0) == :error
      assert String.contains?(elem(result, 1), "Tool execution failed:")
    end

    test "handles empty content list" do
      response = %{
        is_error: true,
        result: %{"content" => []}
      }

      result = ErrorHandler.handle_response_error(response)
      assert elem(result, 0) == :error
      assert String.contains?(elem(result, 1), "Tool execution failed:")
    end

    test "handles content with non-text items only" do
      response = %{
        is_error: true,
        result: %{
          "content" => [
            %{"type" => "image", "data" => "base64"},
            %{"type" => "audio", "data" => "mp3"}
          ]
        }
      }

      result = ErrorHandler.handle_response_error(response)
      assert elem(result, 0) == :error
      assert String.contains?(elem(result, 1), "Tool execution failed:")
    end

    test "handles non-map result gracefully" do
      response = %{
        is_error: true,
        result: "string error message"
      }

      result = ErrorHandler.handle_response_error(response)
      assert elem(result, 0) == :error
      assert String.contains?(elem(result, 1), "Tool execution failed:")
    end

    test "handles nil result" do
      response = %{
        is_error: true,
        result: nil
      }

      result = ErrorHandler.handle_response_error(response)
      assert elem(result, 0) == :error
      assert String.contains?(elem(result, 1), "Tool execution failed:")
    end

    test "handles list result with complex structure" do
      response = %{
        is_error: true,
        result: [%{"type" => "complex", "nested" => %{"data" => "value"}}]
      }

      result = ErrorHandler.handle_response_error(response)
      assert elem(result, 0) == :error
      assert String.contains?(elem(result, 1), "Tool execution failed:")
    end
  end

  describe "should_retry?/1" do
    test "returns true for transient errors that should retry" do
      transient_errors = [
        %Anubis.MCP.Error{reason: :request_timeout},
        %Anubis.MCP.Error{reason: :send_failure},
        %Anubis.MCP.Error{reason: :connection_refused},
        %Anubis.MCP.Error{reason: :internal_error}
      ]

      for error <- transient_errors do
        assert ErrorHandler.should_retry?(error) == true
      end
    end

    test "returns false for permanent errors" do
      permanent_errors = [
        %Anubis.MCP.Error{reason: :parse_error},
        %Anubis.MCP.Error{reason: :invalid_request},
        %Anubis.MCP.Error{reason: :method_not_found},
        %Anubis.MCP.Error{reason: :invalid_params}
      ]

      for error <- permanent_errors do
        assert ErrorHandler.should_retry?(error) == false
      end
    end

    test "returns false for non-MCP errors" do
      other_errors = [
        "connection timeout",
        :timeout,
        {:badarg, [{:erlang, :binary_to_integer, ["abc"], 0}]}
      ]

      for error <- other_errors do
        assert ErrorHandler.should_retry?(error) == false
      end
    end

    test "returns false for unknown reason codes" do
      error = %Anubis.MCP.Error{reason: :unknown_reason}

      assert ErrorHandler.should_retry?(error) == false
    end

    test "handles errors without reason field" do
      # Test edge case where error struct might not have reason field
      error = %{__struct__: Anubis.MCP.Error, code: -32600}

      assert ErrorHandler.should_retry?(error) == false
    end
  end

  describe "wrap_tool_error/3" do
    test "wraps binary error messages correctly" do
      original_error = {:error, "timeout"}

      assert {:error, "Tool 'search' failed: timeout"} =
               ErrorHandler.wrap_tool_error(original_error, "search", %{"query" => "test"})
    end

    test "includes arguments in wrapper for non-binary errors" do
      original_error = {:error, :connection_failed}

      assert {:error, "Tool 'process_data' with args %{\"data\" => 123} failed: :connection_failed"} =
               ErrorHandler.wrap_tool_error(original_error, "process_data", %{"data" => 123})
    end

    test "handles non-tuple errors" do
      original_error = "network unavailable"

      result = ErrorHandler.wrap_tool_error(original_error, "api_call", %{"param" => "value"})
      assert elem(result, 0) == :error
      assert String.contains?(elem(result, 1), "Tool 'api_call' with args")
    end

    test "handles empty arguments map" do
      original_error = {:error, :timeout}

      assert {:error, "Tool 'test' with args %{} failed: :timeout"} =
               ErrorHandler.wrap_tool_error(original_error, "test", %{})
    end

    test "handles complex argument structures" do
      original_error = {:error, :network_error}
      args = %{"nested" => %{"deep" => [%{"array" => true}]}}

      result = ErrorHandler.wrap_tool_error(original_error, "complex_call", args)
      assert elem(result, 0) == :error
      assert String.contains?(elem(result, 1), "Tool 'complex_call' with args")
    end

    test "handles non-binary reason in error tuple" do
      original_error = {:error, %{code: 500, message: "Server error"}}

      result = ErrorHandler.wrap_tool_error(original_error, "api", %{"id" => 123})
      assert elem(result, 0) == :error
      assert String.contains?(elem(result, 1), "Tool 'api' with args")
    end

    test "handles nil arguments gracefully" do
      original_error = {:error, :timeout}

      result = ErrorHandler.wrap_tool_error(original_error, "test", nil)
      assert elem(result, 0) == :error
      assert String.contains?(elem(result, 1), "Tool 'test' with args")
    end

    test "handles list arguments" do
      original_error = {:error, :validation_failed}

      result = ErrorHandler.wrap_tool_error(original_error, "process", [1, 2, 3])
      assert elem(result, 0) == :error
      assert String.contains?(elem(result, 1), "Tool 'process' with args")
    end

    test "handles atom tool names" do
      original_error = {:error, "timeout"}

      result = ErrorHandler.wrap_tool_error(original_error, :test_atom, %{"key" => "value"})
      assert elem(result, 0) == :error
      assert String.contains?(elem(result, 1), "Tool 'test_atom' failed:")
    end
  end
end
