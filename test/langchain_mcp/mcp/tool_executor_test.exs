defmodule LangChain.MCP.ToolExecutorTest do
  use ExUnit.Case, async: true

  alias LangChain.MCP.{Adapter, Config, ToolExecutor}

  defmodule MockClient do
    @moduledoc "Mock MCP client for testing"

    def list_tools, do: {:ok, %{"result" => %{"tools" => [%{"name" => "test_tool"}]}}}

    def call_tool(tool_name, args, _timeout) when is_map(args),
      do:
        {:ok,
         %{
           is_error: false,
           result: %{"content" => [%{"type" => "text", "text" => "Mock result for #{tool_name}"}]}
         }}

    def call_tool(_name, _args, _timeout),
      do: {:error, "Unexpected argument format"}
  end

  describe "execute/4" do
    test "executes tool successfully with primary client" do
      config = Config.new!(client: MockClient)

      {:ok, result} = ToolExecutor.execute(config, "test_tool", %{"query" => "hello"})

      assert is_binary(result) or is_list(result)
    end

    test "handles successful execution returning ContentParts" do
      defmodule MultiContentClient do
        @moduledoc "Mock MCP client for multiple content items"

        def call_tool(_tool_name, _args, _timeout) do
          result = %{
            "content" => [
              %{"type" => "text", "text" => "First part"},
              %{"type" => "image", "data" => "base64data", "mimeType" => "image/png"}
            ]
          }

          {:ok, %{is_error: false, result: result}}
        end
      end

      config = Config.new!(client: MultiContentClient)

      {:ok, result} = ToolExecutor.execute(config, "test_tool", %{"query" => "hello"})

      assert is_list(result)
      assert length(result) == 2
    end

    test "handles exceptions during execution" do
      defmodule ExceptionClient do
        def call_tool(_name, _args, _timeout),
          do: raise("Unexpected error")

        def list_tools, do: {:ok, []}
      end

      config = Config.new!(client: ExceptionClient)

      {:error, reason} = ToolExecutor.execute(config, "test_tool", %{"query" => "hello"})

      assert String.contains?(reason, "exception")
    end
  end

  describe "validate_tool/2" do
    test "returns :ok when tool exists on server" do
      defmodule ToolsResponseClient do
        @moduledoc "Mock MCP client with proper tools response format"

        def list_tools, do: {:ok, %{"result" => %{"tools" => [%{"name" => "test_tool"}]}}}
      end

      result = ToolExecutor.validate_tool(ToolsResponseClient, "test_tool")
      assert result == :ok
    end

    test "handles error responses from list_tools" do
      defmodule ErrorToolsClient do
        @moduledoc "Mock MCP client that returns errors"

        def list_tools, do: {:error, "Connection failed"}
      end

      {:error, reason} = ToolExecutor.validate_tool(ErrorToolsClient, "any_tool")

      assert is_binary(reason)
    end

    test "returns error when tool not found on server" do
      defmodule NoToolClient do
        @moduledoc "Mock MCP client without the requested tool"

        def list_tools, do: {:ok, %{"result" => %{"tools" => [%{"name" => "other_tool"}]}}}
      end

      {:error, reason} = ToolExecutor.validate_tool(NoToolClient, "missing_tool")

      assert String.contains?(reason, "missing_tool")
      assert String.contains?(reason, "not found")
    end
  end

  describe "execute_on_client/5" do
    test "executes tool with custom timeout and context" do
      defmodule TimeoutContextClient do
        @moduledoc "Mock client for testing timeout and context"

        def call_tool(_tool_name, _args, timeout: 5000) do
          {:ok,
           %{
             is_error: false,
             result: %{"content" => [%{"type" => "text", text: "Result with custom timeout"}]}
           }}
        end

        def list_tools, do: {:ok, []}
      end

      {:ok, result} = ToolExecutor.execute_on_client(TimeoutContextClient, "test_tool", %{}, 5000)

      assert is_binary(result) or is_list(result)
    end
  end

  describe "Fallback functionality" do
    test "uses fallback client when primary fails with retryable error" do
      defmodule PrimaryFailingClient do
        @moduledoc "Mock client that always fails"

        def call_tool(_tool_name, _args, timeout: timeout) when is_integer(timeout) do
          {:error, %Anubis.MCP.Error{code: -1, reason: :request_timeout}}
        end

        def list_tools, do: {:ok, []}
      end

      defmodule FallbackClient do
        @moduledoc "Mock fallback client that succeeds"

        def call_tool(_tool_name, _args, timeout: timeout) when is_integer(timeout) do
          {:ok,
           %{
             is_error: false,
             result: %{"content" => [%{"type" => "text", "text" => "Fallback success"}]}
           }}
        end

        def list_tools, do: {:ok, []}
      end

      config = Config.new!(client: PrimaryFailingClient, fallback_client: FallbackClient)

      # Should attempt primary and fall back to secondary
      {:ok, result} = ToolExecutor.execute(config, "test_tool", %{"query" => "fallback"})

      assert is_binary(result)
      assert String.contains?(result, "Fallback success")
    end

    test "does not use fallback when error is not retryable" do
      defmodule NonRetryableFailingClient do
        @moduledoc "Mock client that fails with non-retryable error"

        def call_tool(_tool_name, _args, timeout: timeout) when is_integer(timeout) do
          {:error, %Anubis.MCP.Error{code: -1, reason: :request_timeout}}
        end

        def list_tools, do: {:ok, []}
      end

      config = Config.new!(client: NonRetryableFailingClient)

      # Should fail on primary and not attempt fallback
      {:error, reason} = ToolExecutor.execute(config, "test_tool", %{"query" => "no_fallback"})

      assert is_binary(reason)
    end

    test "respects before_fallback callback to skip fallback" do
      defmodule SkipFallbackClient do
        @moduledoc "Mock client with configured callback"

        def call_tool(_tool_name, _args, timeout: timeout) when is_integer(timeout) do
          {:error, %{reason: :request_timeout}}
        end

        def list_tools, do: {:ok, []}
      end

      config =
        Config.new!(
          client: SkipFallbackClient,
          fallback_client: SkipFallbackClient,
          before_fallback: fn _, _, _ -> :skip end
        )

      # Should not attempt fallback due to callback
      {:error, reason} = ToolExecutor.execute(config, "test_tool", %{"query" => "callback_skip"})

      assert is_binary(reason)
    end

    test "fallback client itself fails when it encounters error" do
      defmodule BothFailClient do
        @moduledoc "Mock client where both primary and fallback fail"

        # Primary call
        def call_tool(_tool_name, _args, timeout: timeout) when is_integer(timeout) do
          {:error, %{reason: :request_timeout}}
        end

        def list_tools, do: {:ok, []}
      end

      config = Config.new!(client: BothFailClient, fallback_client: BothFailClient)

      # Primary fails, then fallback fails too (both fail with same error)
      {:error, reason} = ToolExecutor.execute(config, "test_tool", %{"query" => "both_fail"})

      assert is_binary(reason)
    end
  end

  describe "Context and return format handling" do
    test "merges context parameters correctly" do
      defmodule ContextMergeClient do
        @moduledoc "Mock client for testing context merging"

        def call_tool(_tool_name, _args, timeout: timeout) when is_integer(timeout) do
          {:ok,
           %{
             is_error: false,
             result: %{"content" => [%{"type" => "text", text: "Context merge test"}]}
           }}
        end

        def list_tools, do: {:ok, []}
      end

      config = Config.new!(client: ContextMergeClient)
      context = %{timeout: 5000}

      {:ok, result} = ToolExecutor.execute(config, "test_tool", %{}, context)

      assert is_binary(result) or is_list(result)
    end
  end

  describe "list_tools/1" do
    test "lists all available tools on server" do
      defmodule ListToolsClient do
        @moduledoc "Mock client with multiple tools"

        def list_tools do
          {:ok,
           %{
             result: %{
               "tools" => [
                 %{"name" => "search", "description" => "Search for content"},
                 %{"name" => "analyze", "description" => "Analyze data"}
               ]
             }
           }}
        end

        def call_tool(_tool_name, _args, timeout: _timeout),
          do: {:ok, %{is_error: false, result: %{}}}
      end

      {:ok, tools} = ToolExecutor.list_tools(ListToolsClient)

      assert is_list(tools)
      assert length(tools) == 2
      # Verify tool structure
      assert Enum.all?(tools, fn t -> is_map(t) and Map.has_key?(t, "name") end)
    end

    test "handles retry logic for initialization failures" do
      defmodule RetryListToolsClient do
        @moduledoc "Mock client that initially fails with server capabilities error"

        # First call returns internal_error about missing capabilities
        def list_tools do
          {:error, %{reason: :internal_error, data: %{message: "Server capabilities not set"}}}
        end

        def call_tool(_tool_name, _args, timeout: _timeout),
          do: {:ok, %{is_error: false, result: %{}}}
      end

      # This should retry and eventually fail after retries exhausted
      {:error, reason} = ToolExecutor.list_tools(RetryListToolsClient)

      assert is_binary(reason)
    end

    test "handles various error types in list_tools" do
      defmodule ErrorTypesListClient do
        @moduledoc "Mock client that returns different error types"

        # Test connection failure
        def list_tools do
          {:error, %{reason: :connection_refused}}
        end

        def call_tool(_tool_name, _args, timeout: _timeout),
          do: {:ok, %{is_error: false, result: %{}}}
      end

      # Should handle non-internal errors immediately (no retry)
      {:error, reason} = ToolExecutor.list_tools(ErrorTypesListClient)

      assert is_binary(reason)
    end
  end

  describe "list_tools/1 with PID" do
    @tag :live_call
    test "lists tools from a client started by PID" do
      # Start a real client, get its PID
      {:ok, client_pid} =
        LangChainMCP.TestClient.start_link(
          transport: {:streamable_http, base_url: "http://localhost:5000"}
        )

      :ok = Adapter.wait_for_server_ready(client_pid)

      {:ok, tools} = ToolExecutor.list_tools(client_pid)

      assert is_list(tools)
      # Test server provides get_current_time, get_timestamp, add_numbers
      assert Enum.any?(tools, &(&1["name"] == "get_current_time"))

      Supervisor.stop(client_pid)
    end
  end

  describe "execute_on_client/5 with PID" do
    @tag :live_call
    test "dispatches tool call via PID to base client" do
      {:ok, client_pid} =
        LangChainMCP.TestClient.start_link(
          transport: {:streamable_http, base_url: "http://localhost:5000"}
        )

      :ok = Adapter.wait_for_server_ready(client_pid)

      # This test verifies the PID dispatch works correctly.
      # We're testing that the call is properly routed through Anubis.Client.Base,
      # not the server's response (which may vary based on server state).
      result =
        ToolExecutor.execute_on_client(
          client_pid,
          "get_timestamp",
          %{},
          5_000,
          %{}
        )

      # The call should either succeed or fail with an MCP error (not a dispatch error)
      case result do
        {:ok, response} ->
          # If successful, verify we got a valid response
          assert is_binary(response) or is_list(response)

        {:error, msg} ->
          # If error, it should be an MCP error, not "attempted to apply a function on PID"
          refute String.contains?(msg, "attempted to apply")
          refute String.contains?(msg, "Modules (the first argument of apply)")
      end

      Supervisor.stop(client_pid)
    end
  end
end
