# LangChain MCP Tests

This directory contains tests for the LangChain MCP integration.

## Test Types

### Unit Tests (Mocked)

Most tests use mocked MCP responses and do not require a running MCP server.

```bash
# Run all unit tests
mix test

# Run specific test file
mix test test/langchain/mcp/schema_converter_test.exs
```

### Live Integration Tests

Live tests connect to an actual MCP server running in Docker. These are tagged with `@tag :live_call`.

```bash
# Start MCP test server
docker-compose up -d

# Run live tests
mix test --include live_call

# Run specific live test
mix test test/langchain/mcp/adapter_integration_test.exs --include live_call

# Stop server when done
docker-compose down
```

## Test Server

The test infrastructure uses the `mcp/time` Docker image, which provides:
- `get_current_time` tool - Gets current time in specified timezone

This is a simple, stable reference server perfect for testing.

## Test Structure

```
test/
├── README.md                           # This file
├── test_helper.exs                     # Test setup
├── support/
│   └── mcp_case.ex                     # Common test helpers
└── langchain/mcp/
    ├── config_test.exs                 # Config validation tests
    ├── schema_converter_test.exs       # Schema conversion tests
    ├── content_mapper_test.exs         # Content mapping tests
    ├── error_handler_test.exs          # Error handling tests
    ├── tool_executor_test.exs          # Tool execution tests
    ├── adapter_test.exs                # Adapter unit tests
    └── adapter_integration_test.exs    # Live integration tests
```

## Writing Tests

### Unit Test Example

```elixir
defmodule LangChain.MCP.ConfigTest do
  use ExUnit.Case
  alias LangChain.MCP.Config

  test "creates valid config" do
    config = Config.new!(client: MyApp.MCPClient)
    assert config.client == MyApp.MCPClient
  end
end
```

### Live Test Example

```elixir
defmodule LangChain.MCP.AdapterIntegrationTest do
  use LangChainMCP.MCPCase

  @tag :live_call
  test "discovers tools from real server", %{client: client} do
    adapter = Adapter.new(client: client)
    {:ok, tools} = Adapter.discover_tools(adapter)

    assert length(tools) > 0
  end
end
```

## Troubleshooting

### Docker Server Won't Start

```bash
# Check if port 4000 is already in use
lsof -i :4000

# View server logs
docker-compose logs mcp-time

# Rebuild and restart
docker-compose down
docker-compose up -d --build
```

### Tests Timing Out

The default timeout is 30 seconds. For slow connections:

```elixir
config = Config.new!(client: client, timeout: 60_000)
```

### Connection Refused

Ensure the Docker server is running:

```bash
docker-compose ps
curl http://localhost:5000/health  # If server supports it
```

## CI/CD

For CI environments, you can run unit tests without Docker:

```bash
# Only run fast unit tests
mix test --exclude live_call
```

To run live tests in CI, ensure Docker is available and run:

```bash
docker-compose up -d
mix test --include live_call
docker-compose down
```
