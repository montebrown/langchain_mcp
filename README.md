# LangChain MCP

Model Context Protocol (MCP) integration for LangChain Elixir. This library enables LangChain applications to use MCP servers as tool providers, giving instant access to the growing ecosystem of MCP servers.

## Features

- 🔌 **Easy Integration** - Add MCP tools to your LangChain workflows with minimal code
- 🛠️ **Tool Discovery** - Automatically discover and convert MCP tools to LangChain functions
- 🔄 **Fallback Support** - Configure fallback MCP clients for resilient tool execution
- 📦 **Multi-modal Content** - Full support for text, images, and other content types
- ⚙️ **Configurable** - Cache tool discovery, configure timeouts, async execution
- 🧪 **Testing** - Mock support for unit tests, live test infrastructure with Docker

## Installation

Add `langchain_mcp` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:langchain, "~> 0.4"},
    {:langchain_mcp, "~> 0.1"}
  ]
end
```

## Quick Start

### 1. Define an MCP Client

```elixir
defmodule MyApp.GitHubMCP do
  use LangChain.MCP.Client,
    name: "MyApp",
    version: "1.0.0",
    protocol_version: "2025-03-26"
end
```

### 2. Start the Client in Your Supervision Tree

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {MyApp.GitHubMCP,
       transport: {:streamable_http, base_url: "http://localhost:5000"}}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### 3. Use MCP Tools in Your Chain

```elixir
alias LangChain.Chains.LLMChain
alias LangChain.ChatModels.ChatAnthropic
alias LangChain.Message
alias LangChain.MCP.Adapter

# Create adapter and discover tools
adapter = Adapter.new(client: MyApp.GitHubMCP)
mcp_functions = Adapter.to_functions(adapter)

# Mix with regular functions
all_functions = [
  MyApp.Functions.custom_function()
] ++ mcp_functions

# Use in chain
{:ok, updated_chain} =
  LLMChain.new!(%{llm: ChatAnthropic.new!()})
  |> LLMChain.add_tools(all_functions)
  |> LLMChain.add_message(Message.new_user!("Create a GitHub issue for this bug"))
  |> LLMChain.run(mode: :while_needs_response)
```

## Configuration Options

### Adapter Options

```elixir
adapter = Adapter.new(
  client: MyApp.MCPClient,
  # Cache tool discovery (default: true)
  cache_tools: true,
  # Timeout for tool calls in ms (default: 30_000)
  timeout: 30_000,
  # Mark tools as async (default: false)
  async: false,
  # Fallback client if primary fails
  fallback_client: MyApp.BackupMCPClient,
  # Filter which tools to expose (default: all)
  tool_filter: fn tool -> tool["name"] not in ["dangerous_tool"] end
)
```

### Selective Tool Discovery

```elixir
# Get only specific tools
mcp_functions = Adapter.to_functions(adapter, only: ["search", "fetch"])

# Exclude certain tools
mcp_functions = Adapter.to_functions(adapter, except: ["admin_tool"])
```

## Fallback Support

Similar to LangChain's LLM fallbacks, you can configure fallback MCP clients:

```elixir
adapter = Adapter.new(
  client: MyApp.PrimaryMCP,
  fallback_client: MyApp.BackupMCP,
  # Optional: modify behavior before fallback
  before_fallback: fn _adapter, tool_name, _args ->
    Logger.warning("Falling back for tool: #{tool_name}")
    :continue  # or :skip to skip fallback
  end
)
```

## Testing

### Unit Tests with Mocks

```elixir
defmodule MyApp.MyAgentTest do
  use ExUnit.Case

  setup do
    # Use Anubis mock transport for testing
    {:ok, client} = MyApp.TestMCP.start_link(
      transport: {:mock, responses: %{
        "list_tools" => %{"tools" => [...]},
        "call_tool" => %{"content" => [...]}
      }}
    )

    {:ok, client: client}
  end

  test "agent uses MCP tools", %{client: _client} do
    # Your test here
  end
end
```

### Live Integration Tests

This project includes a built-in Elixir-based MCP test server - no Docker needed!

**Step 1: Start the test server**

```bash
mix test_server
```

This starts an MCP server on `http://localhost:5000` with test tools:
- `get_current_time` - Get current time in UTC or specified timezone
- `get_timestamp` - Get current Unix timestamp
- `add_numbers` - Add two numbers together

**Step 2: Run integration tests** (in a separate terminal)

```bash
mix test --include live_call
```

**Custom port:** If you need to use a different port:

```bash
# Terminal 1: Start server on custom port
mix test_server --port 5000

# Terminal 2: Run tests with custom URL
MCP_TEST_URL=http://localhost:5000 mix test --include live_call
```

Example live test:

```elixir
@tag :live_call
test "integrates with real MCP server" do
  adapter = Adapter.new(client: MyApp.MCPClient)
  functions = Adapter.to_functions(adapter)

  assert length(functions) > 0
end
```

### Using Docker (Optional)

If you prefer Docker or need to test against external MCP servers, you can use docker-compose:

```bash
# Start Docker-based MCP servers
docker-compose up -d

# Run tests
mix test --include live_call
```

**Note:** Most official MCP servers (like `mcp_server_time`) use stdio transport and cannot be accessed via HTTP without a wrapper. The built-in Elixir test server is the recommended approach.

## Available MCP Servers

Many MCP servers are available via Docker Hub:

- `mcp/time` - Time and timezone operations
- `mcp/github` - GitHub API integration
- `mcp/postgres` - PostgreSQL database access
- `mcp/sqlite` - SQLite database operations
- `mcp/puppeteer` - Browser automation

See [Docker Hub MCP Catalog](https://hub.docker.com/mcp) for more.

## Architecture

```
┌─────────────────────────┐
│   LangChain.LLMChain    │
│   + tools: [Function]   │
└────────────┬────────────┘
             │
             ├─── Regular Functions
             │
             └─── MCP Functions (via Adapter)
                  │
                  ▼
         ┌────────────────────┐
         │  LangChain.MCP     │
         │  • Adapter         │
         │  • SchemaConverter │
         │  • ToolExecutor    │
         │  • ContentMapper   │
         │  • ErrorHandler    │
         └────────┬───────────┘
                  │
                  ▼
         ┌────────────────────┐
         │  Anubis.Client     │
         │  (GenServer)       │
         └────────┬───────────┘
                  │
                  ▼
         ┌────────────────────┐
         │   MCP Server       │
         │ (Docker/External)  │
         └────────────────────┘
```

## License

Apache 2.0 License. See LICENSE for details.

## Links

- [LangChain Elixir](https://github.com/brainlid/langchain)
- [Anubis MCP](https://hexdocs.pm/anubis_mcp)
- [Model Context Protocol](https://modelcontextprotocol.io)
- [MCP Servers Catalog](https://hub.docker.com/mcp)
