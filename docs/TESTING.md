# LangChain MCP Testing Guide

Complete guide for testing LangChain MCP integrations.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Test Server Setup](#test-server-setup)
3. [Unit Testing](#unit-testing)
4. [Integration Testing](#integration-testing)
5. [Testing Patterns](#testing-patterns)
6. [Test Helpers](#test-helpers)
7. [Troubleshooting](#troubleshooting)

## Quick Start

### Run Unit Tests (No Server Required)

```bash
mix test
```

All unit tests use mocks and don't require external services.

### Run Integration Tests

**Terminal 1** - Start test server:
```bash
mix test_server
```

**Terminal 2** - Run integration tests:
```bash
mix test --include live_call
```

## Test Server Setup

### Built-In Test Server

The library includes a native Elixir MCP test server with three test tools:

1. **`get_current_time`** - Returns current time (UTC or timezone)
2. **`get_timestamp`** - Returns Unix timestamp
3. **`add_numbers`** - Adds two numbers

### Starting the Test Server

#### Default (Port 4000)

```bash
mix test_server
```

Output:
```
🚀 Starting MCP Test Server on http://localhost:4000
   Tools available: get_current_time, get_timestamp, add_numbers
   Endpoints: /sse (SSE connection), /message (POST messages)
   Press Ctrl+C to stop

Running LangChainMCP.TestServer.Router with Bandit 1.8.0 at 0.0.0.0:4000 (http)
```

#### Custom Port

```bash
mix test_server --port 5000
```

Then set environment variable for tests:
```bash
MCP_TEST_URL=http://localhost:5000 mix test --include live_call
```

### Test Server Architecture

```
┌─────────────────────────────────────┐
│   Bandit HTTP Server (port 4000)    │
│                                     │
│   ┌─────────────────────────────┐   │
│   │  Plug Router                │   │
│   │  - GET /sse                 │   │
│   │  - POST /message            │   │
│   └─────────┬───────────────────┘   │
└─────────────┼───────────────────────┘
              │
              ▼
    ┌─────────────────────────┐
    │  Hermes.Transport.      │
    │  StreamableHTTP.Plug    │
    └─────────┬───────────────┘
              │
              ▼
    ┌─────────────────────────┐
    │  LangChainMCP.          │
    │  TestServer             │
    │  (MCP Server impl)      │
    └─────────────────────────┘
```

### Verifying Server is Running

```bash
# Check SSE endpoint (will hang - that's normal)
curl -H "Accept: text/event-stream" http://localhost:4000/sse

# Should see Server-Sent Events stream open
```

## Unit Testing

### Testing with Mocked Clients

Use `Mimic` to mock Hermes client:

```elixir
defmodule MyApp.AdapterTest do
  use ExUnit.Case, async: true
  use Mimic

  alias LangChain.MCP.Adapter
  alias Hermes.MCP.Response

  setup :verify_on_exit!

  describe "to_functions/1" do
    test "converts MCP tools to LangChain functions" do
      # Mock client
      expect(MockClient, :list_tools, fn _ ->
        {:ok, %Response{
          result: %{
            "tools" => [
              %{
                "name" => "test_tool",
                "description" => "A test tool",
                "inputSchema" => %{
                  "type" => "object",
                  "properties" => %{
                    "arg1" => %{"type" => "string"}
                  },
                  "required" => ["arg1"]
                }
              }
            ]
          }
        }}
      end)

      # Test
      {:ok, adapter} = Adapter.new(client: MockClient)
      functions = Adapter.to_functions(adapter)

      assert length(functions) == 1
      assert hd(functions).name == "test_tool"
    end
  end
end
```

### Testing Schema Conversion

```elixir
defmodule LangChain.MCP.SchemaConverterTest do
  use ExUnit.Case

  alias LangChain.MCP.SchemaConverter
  alias LangChain.FunctionParam

  test "converts JSON Schema to FunctionParam" do
    schema = %{
      "type" => "object",
      "properties" => %{
        "query" => %{
          "type" => "string",
          "description" => "Search query"
        },
        "limit" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 100
        }
      },
      "required" => ["query"]
    }

    params = SchemaConverter.convert_input_schema(schema)

    assert length(params) == 2

    query_param = Enum.find(params, &(&1.name == "query"))
    assert query_param.type == :string
    assert query_param.required == true

    limit_param = Enum.find(params, &(&1.name == "limit"))
    assert limit_param.type == :integer
    assert limit_param.required == false
    assert String.contains?(limit_param.description, ">= 1")
  end

  test "handles enum types" do
    schema = %{
      "type" => "object",
      "properties" => %{
        "status" => %{
          "type" => "string",
          "enum" => ["open", "closed", "pending"]
        }
      }
    }

    params = SchemaConverter.convert_input_schema(schema)

    status_param = hd(params)
    assert status_param.enum == ["open", "closed", "pending"]
  end
end
```

### Testing Content Mapping

```elixir
defmodule LangChain.MCP.ContentMapperTest do
  use ExUnit.Case

  alias LangChain.MCP.ContentMapper
  alias LangChain.ContentPart

  test "maps text content" do
    content = [%{"type" => "text", "text" => "Hello"}]
    parts = ContentMapper.map_content(content)

    assert length(parts) == 1
    assert hd(parts).type == :text
    assert hd(parts).content == "Hello"
  end

  test "maps image content" do
    content = [%{
      "type" => "image",
      "data" => "base64data",
      "mimeType" => "image/png"
    }]

    parts = ContentMapper.map_content(content)

    assert hd(parts).type == :image
    assert hd(parts).content == "base64data"
    assert hd(parts).options.media == "image/png"
  end

  test "maps mixed content" do
    content = [
      %{"type" => "text", "text" => "Result:"},
      %{"type" => "image", "data" => "...", "mimeType" => "image/jpeg"}
    ]

    parts = ContentMapper.map_content(content)
    assert length(parts) == 2
  end
end
```

### Testing Error Handling

```elixir
defmodule LangChain.MCP.ErrorHandlerTest do
  use ExUnit.Case

  alias LangChain.MCP.ErrorHandler
  alias Hermes.MCP.{Error, Response}

  test "classifies protocol errors as retryable" do
    error = %Error{code: -32601, reason: :method_not_found}
    {type, retryable, _msg} = ErrorHandler.classify_error(error)

    assert type == :protocol
    assert retryable == true
  end

  test "classifies transport errors as retryable" do
    error = %Error{reason: :send_failure}
    {type, retryable, _msg} = ErrorHandler.classify_error(error)

    assert type == :transport
    assert retryable == true
  end

  test "classifies domain errors as not retryable" do
    error = %Response{is_error: true, result: %{"isError" => true}}
    {type, retryable, _msg} = ErrorHandler.classify_error(error)

    assert type == :domain
    assert retryable == false
  end
end
```

## Integration Testing

Integration tests use the real test server and are tagged with `@tag :live_call`.

### Basic Integration Test

```elixir
defmodule LangChain.MCP.AdapterIntegrationTest do
  use LangChain.MCP.MCPCase

  @tag :live_call
  test "discovers tools from test server", %{client: client} do
    {:ok, adapter} = Adapter.new(client: client)
    tools = Adapter.to_functions(adapter)

    assert length(tools) == 3
    tool_names = Enum.map(tools, & &1.name)
    assert "get_current_time" in tool_names
    assert "get_timestamp" in tool_names
    assert "add_numbers" in tool_names
  end

  @tag :live_call
  test "executes tool successfully", %{client: client} do
    {:ok, adapter} = Adapter.new(client: client)
    tools = Adapter.to_functions(adapter)

    add_numbers = Enum.find(tools, &(&1.name == "add_numbers"))
    {:ok, result} = add_numbers.function.(%{"a" => 5, "b" => 3}, %{})

    assert is_list(result)
    [content] = result
    assert String.contains?(content.content, "8")
  end
end
```

### Testing with Live LLM

```elixir
defmodule LangChain.MCP.LLMIntegrationTest do
  use LangChain.MCP.MCPCase

  @tag :live_call
  @tag :live_llm
  test "LLM can use MCP tools", %{client: client} do
    # Requires ANTHROPIC_API_KEY in environment
    api_key = System.get_env("ANTHROPIC_API_KEY")
    if api_key do
      {:ok, adapter} = Adapter.new(client: client)
      tools = Adapter.to_functions(adapter)

      {:ok, chain} =
        LLMChain.new!(%{
          llm: ChatAnthropic.new!(%{
            model: "claude-3-5-sonnet-20241022",
            api_key: api_key
          })
        })
        |> LLMChain.add_tools(tools)
        |> LLMChain.add_message(
          Message.new_user!("What is 42 plus 13?")
        )
        |> LLMChain.run(mode: :while_needs_response)

      final_message = List.last(chain.messages)
      assert String.contains?(final_message.content, "55")
    else
      IO.puts("Skipping LLM test - no API key")
    end
  end
end
```

### Testing Error Conditions

```elixir
defmodule LangChain.MCP.ErrorIntegrationTest do
  use LangChain.MCP.MCPCase

  @tag :live_call
  test "handles unknown tool gracefully", %{client: client} do
    config = Config.new!(client: client)

    result = ToolExecutor.execute_tool(
      config,
      "nonexistent_tool",
      %{}
    )

    assert {:error, _} = result
  end

  @tag :live_call
  test "handles invalid parameters", %{client: client} do
    config = Config.new!(client: client)

    result = ToolExecutor.execute_tool(
      config,
      "add_numbers",
      %{"a" => "not a number", "b" => 5}
    )

    assert {:error, _} = result
  end

  @tag :live_call
  test "handles timeout", %{client: client} do
    config = Config.new!(client: client, timeout: 1)  # 1ms timeout

    result = ToolExecutor.execute_tool(
      config,
      "get_current_time",
      %{}
    )

    # May timeout or succeed depending on timing
    assert match?({:ok, _}, result) or match?({:error, _}, result)
  end
end
```

## Testing Patterns

### Pattern 1: Using MCPCase

Create reusable test setup:

```elixir
defmodule LangChain.MCP.MCPCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use ExUnit.Case
      import LangChain.MCP.MCPCase
    end
  end

  setup tags do
    if tags[:live_call] do
      # Setup for integration tests
      client_module = Module.concat([LangChain.MCP.Test, "Client#{:rand.uniform(10000)}"])

      defmodule client_module do
        use Hermes.Client,
          name: "TestClient",
          version: "1.0.0",
          protocol_version: "2025-03-26"
      end

      test_url = System.get_env("MCP_TEST_URL", "http://localhost:4000")

      {:ok, _pid} = client_module.start_link(
        transport: {:streamable_http, base_url: test_url},
        name: :"test_client_#{:rand.uniform(10000)}"
      )

      {:ok, client: client_module}
    else
      # Unit test setup
      :ok
    end
  end
end
```

### Pattern 2: Async vs Sync Tests

```elixir
# Unit tests can be async (use mocks)
defmodule MyApp.FastTest do
  use ExUnit.Case, async: true

  test "fast unit test" do
    # No external dependencies
  end
end

# Integration tests must be sync (share test server)
defmodule MyApp.IntegrationTest do
  use ExUnit.Case, async: false

  @tag :live_call
  test "integration test" do
    # Uses test server
  end
end
```

### Pattern 3: Test Fixtures

```elixir
defmodule MyApp.Fixtures do
  def tool_definition do
    %{
      "name" => "test_tool",
      "description" => "A test tool",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "arg1" => %{"type" => "string"}
        },
        "required" => ["arg1"]
      }
    }
  end

  def mock_response(tools) do
    %Response{
      result: %{"tools" => tools},
      is_error: false
    }
  end
end

# Use in tests
test "something" do
  tool = Fixtures.tool_definition()
  response = Fixtures.mock_response([tool])
  # ...
end
```

### Pattern 4: Property-Based Testing

```elixir
defmodule LangChain.MCP.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  property "schema conversion is reversible" do
    check all(
      param_count <- integer(1..10),
      names <- list_of(string(:alphanumeric), length: param_count),
      types <- list_of(member_of([:string, :number, :integer]), length: param_count)
    ) do
      # Create params
      params = Enum.zip(names, types)
      |> Enum.map(fn {name, type} ->
        FunctionParam.new!(%{name: name, type: type, required: false})
      end)

      # Convert to JSON Schema and back
      schema = SchemaConverter.to_json_schema(params)
      converted = SchemaConverter.convert_input_schema(schema)

      # Should match original (order may differ)
      assert length(converted) == length(params)
      Enum.each(params, fn param ->
        assert Enum.any?(converted, fn c ->
          c.name == param.name && c.type == param.type
        end)
      end)
    end
  end
end
```

## Test Helpers

### Custom Assertions

```elixir
defmodule LangChain.MCP.TestHelpers do
  import ExUnit.Assertions

  def assert_tool_available(tools, tool_name) do
    assert Enum.any?(tools, &(&1.name == tool_name)),
      "Expected tool #{tool_name} to be available, got: #{inspect(Enum.map(tools, & &1.name))}"
  end

  def assert_valid_function(function) do
    assert %Function{} = function
    assert is_binary(function.name)
    assert is_function(function.function, 2)
    assert is_list(function.parameters)
  end

  def assert_content_part(part, type) do
    assert %ContentPart{} = part
    assert part.type == type
    assert is_binary(part.content)
  end
end
```

### Test Data Generators

```elixir
defmodule LangChain.MCP.Generators do
  def generate_tool(name \\ "test_tool") do
    %{
      "name" => name,
      "description" => "Test tool: #{name}",
      "inputSchema" => generate_schema()
    }
  end

  def generate_schema do
    %{
      "type" => "object",
      "properties" => %{
        "param1" => %{"type" => "string"},
        "param2" => %{"type" => "integer"}
      },
      "required" => ["param1"]
    }
  end

  def generate_content(type \\ "text") do
    case type do
      "text" -> %{"type" => "text", "text" => "Test content"}
      "image" -> %{"type" => "image", "data" => "base64", "mimeType" => "image/png"}
    end
  end
end
```

### Mock Factories

```elixir
defmodule LangChain.MCP.MockFactory do
  alias Hermes.MCP.{Response, Error}

  def build_response(result) do
    %Response{
      result: result,
      is_error: false,
      id: "test-id",
      method: "test/method"
    }
  end

  def build_error_response(message) do
    %Response{
      result: %{"isError" => true, "message" => message},
      is_error: true
    }
  end

  def build_protocol_error(code, reason) do
    %Error{
      code: code,
      reason: reason,
      message: "Test error",
      data: %{}
    }
  end
end
```

## Troubleshooting

### Tests Failing with Connection Errors

**Problem:** `{:error, :econnrefused}`

**Solution:**
1. Ensure test server is running: `mix test_server`
2. Check server is on correct port
3. Verify with `curl http://localhost:4000/sse`

### Tests Hanging

**Problem:** Tests never complete

**Solution:**
1. Check for deadlocks in GenServer calls
2. Verify timeout values are reasonable
3. Use `@tag timeout: 60_000` for slow tests
4. Check test server logs for errors

### Intermittent Failures

**Problem:** Tests pass sometimes, fail other times

**Solution:**
1. Ensure integration tests are `async: false`
2. Add proper test isolation (unique client names)
3. Clean up resources in `on_exit` callbacks
4. Check for race conditions

### Mock Not Working

**Problem:** Mimic expects not being called

**Solution:**
1. Add `setup :verify_on_exit!`
2. Ensure mock is for correct module
3. Check function arity matches
4. Verify test is calling mocked code path

### Port Already in Use

**Problem:** Test server won't start

**Solution:**
```bash
# Find what's using port 4000
lsof -i :4000

# Kill the process
kill -9 <PID>

# Or use different port
mix test_server --port 5000
MCP_TEST_URL=http://localhost:5000 mix test --include live_call
```

### Test Server Crashes

**Problem:** Test server exits unexpectedly

**Solution:**
1. Check logs for error messages
2. Verify Hermes dependencies are installed
3. Check tool implementations for bugs
4. Ensure Bandit server can start

### Slow Tests

**Problem:** Test suite takes too long

**Solution:**
1. Run only specific tests: `mix test test/specific_test.exs`
2. Skip integration tests in development: `mix test --exclude live_call`
3. Use `async: true` where possible
4. Profile slow tests: `mix test --trace`

## Test Organization

### Recommended Structure

```
test/
├── langchain/
│   └── mcp/
│       ├── adapter_test.exs          # Adapter unit tests
│       ├── config_test.exs           # Config validation tests
│       ├── schema_converter_test.exs # Schema conversion tests
│       ├── content_mapper_test.exs   # Content mapping tests
│       ├── error_handler_test.exs    # Error handling tests
│       ├── tool_executor_test.exs    # Tool execution tests
│       └── integration/
│           ├── adapter_integration_test.exs
│           ├── tool_execution_integration_test.exs
│           └── llm_integration_test.exs
├── support/
│   ├── mcp_case.ex                   # Test case template
│   ├── test_helpers.ex               # Helper functions
│   ├── generators.ex                 # Data generators
│   └── mock_factory.ex               # Mock builders
└── test_helper.exs                   # Test configuration
```

### Test Naming Conventions

```elixir
# Unit test
test "converts string type to FunctionParam" do
  # ...
end

# Integration test
@tag :live_call
test "discovers tools from live server" do
  # ...
end

# Property test
property "schema conversion is reversible for all valid inputs" do
  # ...
end

# Edge case
test "handles empty tool list gracefully" do
  # ...
end
```

## Continuous Integration

### GitHub Actions Example

```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      test-server:
        # Use test server as service
        # (Not applicable for mix task, run in step instead)

    steps:
      - uses: actions/checkout@v3

      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'

      - name: Install dependencies
        run: mix deps.get

      - name: Run unit tests
        run: mix test

      - name: Start test server
        run: mix test_server &

      - name: Wait for server
        run: sleep 2

      - name: Run integration tests
        run: mix test --include live_call
```

---

## Next Steps

- **Integration Patterns:** See [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)
- **API Reference:** See [API_REFERENCE.md](API_REFERENCE.md)
- **Architecture:** See [ARCHITECTURE.md](ARCHITECTURE.md)

---

**Last Updated:** 2025-11-10
