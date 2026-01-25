defmodule LangChain.MCP.TestSupport do
  @moduledoc """
  Test support helpers for mocking MCP clients using Mimic.

  This module provides utilities to easily mock MCP tool discovery and execution
  in your tests without requiring a live MCP server.

  ## Setup

  Add Mimic to your test helper:

      # test/test_helper.exs
      Mimic.copy(LangChain.MCP.Adapter)
      Mimic.copy(LangChain.MCP.ToolExecutor)
      ExUnit.start()

  ## Usage Examples

  ### Simple tool stubbing

      use ExUnit.Case, async: true
      use Mimic

      test "agent uses search tool" do
        # Stub tools to return from adapter
        TestSupport.stub_tools(%{
          "search" => fn args ->
            "Found results for: \#{args["query"]}"
          end
        })

        adapter = Adapter.new(client: MyApp.MCPClient)
        functions = Adapter.to_functions(adapter)

        # Functions are now available and will use stubbed responses
        search_fn = Enum.find(functions, &(&1.name == "search"))
        assert search_fn.function.(%{"query" => "elixir"}, %{}) =~ "Found results"
      end

  ### Stubbing with multiple tools

      test "agent uses multiple tools" do
        TestSupport.stub_tools(%{
          "search" => fn %{"query" => q} -> "Results: \#{q}" end,
          "fetch" => fn %{"url" => u} -> "Content from \#{u}" end,
          "analyze" => fn _ -> "Analysis complete" end
        })

        # Your test code here
      end

  ### Stub tool discovery separately

      test "discovers tools" do
        tools = [
          %{
            "name" => "search",
            "description" => "Search for information",
            "inputSchema" => %{
              "type" => "object",
              "properties" => %{"query" => %{"type" => "string"}},
              "required" => ["query"]
            }
          }
        ]

        TestSupport.stub_list_tools(tools)

        adapter = Adapter.new(client: MyApp.MCPClient)
        {:ok, discovered} = Adapter.discover_tools(adapter)

        assert length(discovered) == 1
      end

  ### Stub tool execution with error responses

      test "handles tool errors" do
        TestSupport.stub_tool_call("search", {:error, "API rate limit exceeded"})

        # Your test code that expects error handling
      end

  ### Custom response format

      test "handles multi-content responses" do
        TestSupport.stub_tool_call("analyze", [
          %ContentPart{type: :text, content: "Analysis results"},
          %ContentPart{type: :image, content: "base64data"}
        ])

        # Test code here
      end
  """

  alias LangChain.MCP.Adapter
  alias LangChain.MCP.ToolExecutor

  # Use apply/3 to call Mimic dynamically, avoiding compile-time dependency.
  # This allows the module to compile in :dev/:prod without Mimic being present.
  # credo:disable-for-next-line Credo.Check.Refactor.Apply
  defp mimic_stub(module, function, fun), do: apply(Mimic, :stub, [module, function, fun])

  @doc """
  Stubs MCP tools at the Adapter level with automatic schema generation.

  This is the recommended high-level API for most tests. It automatically:
  - Creates tool schemas with common patterns
  - Stubs `Adapter.to_functions/2` to return stubbed functions
  - Makes stubbed tools callable with your provided response functions

  ## Parameters

    * `tools_map` - Map of tool name to response function or static response
      - Keys: Tool names (strings)
      - Values: Either a function `(args -> result)` or a static result

  ## Examples

      # With response functions
      TestSupport.stub_tools(%{
        "search" => fn args -> "Results for \#{args["query"]}" end,
        "fetch" => fn args -> "Content from \#{args["url"]}" end
      })

      # With static responses
      TestSupport.stub_tools(%{
        "get_time" => "2024-01-15 10:30:00 UTC",
        "get_status" => "OK"
      })

      # Mixed
      TestSupport.stub_tools(%{
        "dynamic" => fn args -> compute_result(args) end,
        "static" => "Fixed response"
      })
  """
  @spec stub_tools(map()) :: :ok
  def stub_tools(tools_map) when is_map(tools_map) do
    # Generate tool schemas
    tools = Enum.map(tools_map, fn {name, _response} -> generate_tool_schema(name) end)

    # Stub list_tools to return the schemas
    stub_list_tools(tools)

    # Stub all tool executions at once
    stub_tool_calls(tools_map)

    :ok
  end

  @doc """
  Stubs tool discovery to return a specific list of tools.

  Use this for fine-grained control over tool schemas, or when you need
  to test tool discovery independently from execution.

  ## Parameters

    * `tools` - List of tool maps with MCP tool schema format

  ## Examples

      tools = [
        %{
          "name" => "search",
          "description" => "Search for information",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "query" => %{"type" => "string", "description" => "Search query"}
            },
            "required" => ["query"]
          }
        },
        %{
          "name" => "fetch",
          "description" => "Fetch URL content",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "url" => %{"type" => "string"}
            }
          }
        }
      ]

      TestSupport.stub_list_tools(tools)
  """
  @spec stub_list_tools([map()]) :: :ok
  def stub_list_tools(tools) when is_list(tools) do
    mimic_stub(ToolExecutor, :list_tools, fn _client ->
      {:ok, tools}
    end)

    :ok
  end

  @doc """
  Stubs a specific tool's execution.

  ## Parameters

    * `tool_name` - Name of the tool to stub
    * `response` - Response to return (function, static value, or error tuple)
      - Function: `(args -> result)` for dynamic responses
      - Static value: String or list of ContentParts
      - Error: `{:error, reason}` tuple

  ## Examples

      # Dynamic response based on args
      TestSupport.stub_tool_call("search", fn args ->
        "Results for: \#{args["query"]}"
      end)

      # Static string response
      TestSupport.stub_tool_call("get_time", "2024-01-15 10:30:00")

      # ContentParts response
      TestSupport.stub_tool_call("analyze", [
        %ContentPart{type: :text, content: "Results"},
        %ContentPart{type: :image, content: "data"}
      ])

      # Error response
      TestSupport.stub_tool_call("failing_tool", {:error, "Service unavailable"})
  """
  @spec stub_tool_call(String.t(), function() | term() | {:error, term()}) :: :ok
  def stub_tool_call(tool_name, response) when is_binary(tool_name) do
    mimic_stub(ToolExecutor, :execute, fn _config, name, args, _context ->
      handle_tool_call(name, tool_name, args, response)
    end)

    :ok
  end

  # Helper for stub_tool_call to reduce nesting
  defp handle_tool_call(name, tool_name, args, response) when name == tool_name do
    case response do
      fun when is_function(fun, 1) ->
        {:ok, fun.(args)}

      {:error, _reason} = error ->
        error

      static_response ->
        {:ok, static_response}
    end
  end

  defp handle_tool_call(name, _tool_name, _args, _response) do
    {:error, "Tool '#{name}' not stubbed"}
  end

  @doc """
  Stubs multiple tool executions at once.

  Convenience function for stubbing several tools with a single call.

  ## Parameters

    * `responses_map` - Map of tool name to response (same format as `stub_tool_call/2`)

  ## Examples

      TestSupport.stub_tool_calls(%{
        "search" => fn args -> "Results: \#{args["query"]}" end,
        "fetch" => "Fetched content",
        "error_tool" => {:error, "Failed"}
      })
  """
  @spec stub_tool_calls(map()) :: :ok
  def stub_tool_calls(responses_map) when is_map(responses_map) do
    mimic_stub(ToolExecutor, :execute, fn _config, name, args, _context ->
      case Map.get(responses_map, name) do
        nil ->
          {:error, "Tool '#{name}' not stubbed"}

        fun when is_function(fun, 1) ->
          {:ok, fun.(args)}

        {:error, _reason} = error ->
          error

        static_response ->
          {:ok, static_response}
      end
    end)

    :ok
  end

  @doc """
  Stubs tool execution with a custom function that receives all parameters.

  Use this for advanced scenarios where you need access to config, context,
  or want to implement custom logic based on multiple parameters.

  ## Parameters

    * `stub_fn` - Function with signature `(config, tool_name, args, context -> result)`

  ## Examples

      # Custom logic based on tool name and args
      TestSupport.stub_tool_execution(fn _config, tool_name, args, _context ->
        case tool_name do
          "search" ->
            {:ok, "Found: \#{args["query"]}"}

          "fetch" ->
            if valid_url?(args["url"]) do
              {:ok, "Content"}
            else
              {:error, "Invalid URL"}
            end

          _ ->
            {:error, "Unknown tool"}
        end
      end)

      # Track calls
      TestSupport.stub_tool_execution(fn _config, tool_name, args, _context ->
        send(self(), {:tool_called, tool_name, args})
        {:ok, "Response"}
      end)
  """
  @spec stub_tool_execution((term(), String.t(), map(), map() -> {:ok, term()} | {:error, term()})) ::
          :ok
  def stub_tool_execution(stub_fn) when is_function(stub_fn, 4) do
    mimic_stub(ToolExecutor, :execute, stub_fn)
    :ok
  end

  @doc """
  Creates a complete mock adapter that works without Mimic stubs.

  This creates an Adapter struct with pre-configured tools that can be used
  directly in tests. Useful when you want to avoid Mimic or need portable
  test fixtures.

  ## Parameters

    * `tools_config` - Keyword list with `:tools` and optionally `:responses`

  ## Options

    * `:tools` - List of tool schemas (same format as `stub_list_tools/1`)
    * `:responses` - Map of tool name to response (optional, defaults to empty)

  ## Examples

      adapter = TestSupport.create_mock_adapter(
        tools: [
          %{
            "name" => "search",
            "description" => "Search",
            "inputSchema" => %{"type" => "object", "properties" => %{}}
          }
        ],
        responses: %{
          "search" => fn args -> "Results: \#{args["query"]}" end
        }
      )

      # Use the adapter in tests
      functions = Adapter.to_functions(adapter)

  Note: This function requires additional implementation to work without
  a real client. For most tests, use `stub_tools/1` instead.
  """
  @spec create_mock_adapter(keyword()) :: LangChain.MCP.Adapter.t()
  def create_mock_adapter(tools_config) do
    tools = Keyword.fetch!(tools_config, :tools)
    responses = Keyword.get(tools_config, :responses, %{})

    # For now, this returns a standard adapter
    # In a real implementation, this would create a mock client module
    # that doesn't require external stubs

    # Create a mock client module at runtime
    mock_client = create_mock_client_module(tools, responses)

    Adapter.new(client: mock_client)
  end

  # Private helpers

  # Generates a basic tool schema for a given tool name
  defp generate_tool_schema(name) when is_binary(name) do
    %{
      "name" => name,
      "description" => "Test tool: #{name}",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{},
        "additionalProperties" => true
      }
    }
  end

  # Creates a mock client module at runtime
  # Note: This is a simplified version for demonstration
  # A full implementation would need defmodule with proper callbacks
  defp create_mock_client_module(_tools, _responses) do
    # This would need to dynamically create a module
    # For now, we'll return a placeholder
    # In real implementation, you'd use Module.create or similar
    LangChain.MCP.TestSupport.MockClient
  end

  defmodule MockClient do
    @moduledoc false
    # Placeholder mock client
    # This would be dynamically generated in a full implementation

    def list_tools do
      {:ok, []}
    end

    def call_tool(_name, _args, _opts) do
      {:ok, %{is_error: false, result: %{"content" => [%{"type" => "text", "text" => "Mock"}]}}}
    end
  end
end
