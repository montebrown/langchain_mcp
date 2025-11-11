# LangChain MCP Documentation

Complete documentation for integrating Model Context Protocol (MCP) with LangChain Elixir.

## What is This?

This library (`langchain_mcp`) provides seamless integration between [LangChain Elixir](https://github.com/brainlid/langchain) and the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/), enabling LLM agents to discover and use tools from any MCP-compatible server.

**Key Features:**
- Automatic tool discovery from MCP servers
- JSON Schema to LangChain parameter conversion
- Multi-modal content support (text, images)
- Fallback mechanisms for resilience
- Full error handling and retry logic
- Compatible with any MCP server implementation

## Quick Start

```elixir
# 1. Add to mix.exs
{:langchain_mcp, "~> 0.1.0"}

# 2. Define an MCP client
defmodule MyApp.GitHubMCP do
  use Hermes.Client,
    name: "MyApp",
    version: "1.0.0",
    protocol_version: "2025-03-26"
end

# 3. Start in supervision tree
children = [
  {MyApp.GitHubMCP,
   transport: {:streamable_http, base_url: "http://localhost:5000"}}
]

# 4. Discover and use tools
adapter = LangChain.MCP.Adapter.new(client: MyApp.GitHubMCP)
mcp_tools = LangChain.MCP.Adapter.to_functions(adapter)

# 5. Use in your LLM chain
{:ok, chain} =
  LLMChain.new!(%{llm: ChatAnthropic.new!()})
  |> LLMChain.add_tools(mcp_tools)
  |> LLMChain.add_message(Message.new_user!("Create a GitHub issue"))
  |> LLMChain.run(mode: :while_needs_response)
```

## Documentation Structure

### For New Users

1. Start here: **README.md** (this file) - Overview and quick start
2. Follow: **[INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)** - Practical usage patterns
3. Reference: **[API_REFERENCE.md](API_REFERENCE.md)** - Complete API documentation

### For Developers

1. **[ARCHITECTURE.md](ARCHITECTURE.md)** - System design and implementation details
2. **[TESTING.md](TESTING.md)** - Testing guide and operational instructions
3. **[REFERENCE.md](REFERENCE.md)** - Schemas, troubleshooting, and advanced topics

## Core Concepts

### MCP Servers

MCP servers expose tools, resources, and prompts that LLMs can use. They can:
- Run as separate processes (stdio transport)
- Run as HTTP services (streamable_http transport)
- Provide dynamic tool discovery
- Support multi-modal content (text, images, audio)

### Hermes Client

[Hermes](https://github.com/the-mikedavis/hermes) is the Elixir MCP client library that handles:
- Protocol communication (JSON-RPC 2.0)
- Transport layer (stdio, HTTP, SSE, WebSocket)
- Request/response lifecycle
- Error handling

### LangChain MCP Adapter

This library bridges Hermes and LangChain by:
- Discovering tools from MCP servers
- Converting JSON Schema to LangChain parameters
- Executing tools through Hermes
- Handling errors and fallbacks
- Mapping content to LangChain format

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                  LangChain Application                   │
│  (LLMChain, Messages, Functions)                        │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│            LangChain.MCP.Adapter                         │
│  • Tool discovery                                        │
│  • Schema conversion                                     │
│  • Function execution                                    │
│  • Error handling                                        │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│              Hermes.Client                               │
│  • list_tools()                                          │
│  • call_tool(name, args)                                 │
│  • Protocol handling                                     │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│           Transport Layer                                │
│  (STDIO, HTTP, SSE, WebSocket)                          │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
        ┌────────────────────┐
        │   MCP Server        │
        │  (External Process) │
        └────────────────────┘
```

## Key Features Explained

### Automatic Schema Conversion

MCP tools use JSON Schema for parameters. This library automatically converts them to LangChain's FunctionParam format:

```elixir
# MCP Tool Definition
%{
  "name" => "search",
  "inputSchema" => %{
    "type" => "object",
    "properties" => %{
      "query" => %{"type" => "string"},
      "limit" => %{"type" => "integer"}
    },
    "required" => ["query"]
  }
}

# Automatically converted to LangChain Function
%Function{
  name: "search",
  parameters: [
    %FunctionParam{name: "query", type: :string, required: true},
    %FunctionParam{name: "limit", type: :integer, required: false}
  ]
}
```

### Multi-Modal Content

MCP tools can return various content types:

```elixir
# MCP Response
%{
  "content" => [
    %{"type" => "text", "text" => "Result text"},
    %{"type" => "image", "data" => "base64...", "mimeType" => "image/png"}
  ]
}

# Mapped to LangChain ContentParts
[
  ContentPart.text!("Result text"),
  ContentPart.image!("base64...", media: "image/png")
]
```

### Error Handling

Three types of errors are handled distinctly:

1. **Protocol Errors** - Communication issues (JSON-RPC errors)
2. **Transport Errors** - Connection problems (network errors)
3. **Domain Errors** - Tool execution failures (application errors)

Only transient errors (protocol/transport) trigger fallback mechanisms.

### Fallback Support

Similar to LangChain's LLM fallbacks:

```elixir
config = Config.new!(
  client: PrimaryMCP,
  fallback_client: BackupMCP,
  before_fallback: fn error, context ->
    Logger.warning("Primary failed: #{inspect(error)}, trying fallback")
  end
)
```

## Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:langchain, "~> 0.4"},
    {:langchain_mcp, "~> 0.1.0"},
    {:hermes_mcp, "~> 0.14"}
  ]
end
```

## Testing Your Integration

```bash
# Run unit tests (mocked, no server required)
mix test

# Start test server
mix test_server

# Run integration tests (requires test server)
mix test --include live_call
```

See **[TESTING.md](TESTING.md)** for detailed testing instructions.

## Common Use Cases

### 1. GitHub Operations

```elixir
# Connect to GitHub MCP server
{:ok, _} = MyApp.GitHubMCP.start_link(
  transport: {:streamable_http, base_url: "http://localhost:3000"}
)

# Discover and use tools
adapter = Adapter.new(client: MyApp.GitHubMCP, cache: true)
tools = Adapter.to_functions(adapter)

# Tools now available: create_issue, list_prs, etc.
```

### 2. Filesystem Operations

```elixir
# Connect to filesystem MCP server
{:ok, _} = MyApp.FileSystemMCP.start_link(
  transport: {:stdio, command: "npx", args: ["@modelcontextprotocol/server-filesystem", "/path"]}
)

# Tools: read_file, write_file, list_directory, etc.
```

### 3. Multiple MCP Servers

```elixir
# Combine tools from multiple servers
github_tools = Adapter.new(client: GitHubMCP) |> Adapter.to_functions()
fs_tools = Adapter.new(client: FileSystemMCP) |> Adapter.to_functions()
custom_tools = [my_custom_function()]

all_tools = github_tools ++ fs_tools ++ custom_tools

# Use in chain
LLMChain.new!(%{llm: llm})
|> LLMChain.add_tools(all_tools)
```

## Configuration Options

### Adapter Configuration

```elixir
LangChain.MCP.Adapter.new(
  client: MyMCP,                    # Required: Hermes client module
  fallback_client: BackupMCP,       # Optional: Fallback client
  cache: true,                      # Optional: Cache tool discovery (default: true)
  timeout: 30_000,                  # Optional: Request timeout (default: 30s)
  async: true,                      # Optional: Async execution (default: true)
  filter: :only,                    # Optional: Tool filtering
  filter_list: ["search", "fetch"], # Optional: Tools to include/exclude
  filter_fn: &my_filter/1,          # Optional: Custom filter function
  before_fallback: &log_error/2     # Optional: Callback before fallback
)
```

### Tool Filtering

```elixir
# Include only specific tools
config = Config.new!(
  client: MyMCP,
  filter: :only,
  filter_list: ["search", "create_issue"]
)

# Exclude specific tools
config = Config.new!(
  client: MyMCP,
  filter: :except,
  filter_list: ["dangerous_operation"]
)

# Custom filter function
config = Config.new!(
  client: MyMCP,
  filter_fn: fn tool ->
    String.starts_with?(tool["name"], "safe_")
  end
)
```

## Troubleshooting

### Connection Errors

**Problem:** `{:error, :econnrefused}`

**Solution:** Ensure MCP server is running and reachable:
```bash
# Check server is listening
curl http://localhost:5000/health

# Check Hermes client configuration
{:ok, _} = MyMCP.start_link(
  transport: {:streamable_http, base_url: "http://localhost:5000"}
)
```

### Schema Conversion Errors

**Problem:** Tool parameters not converting correctly

**Solution:** Check JSON Schema format:
```elixir
# Supported JSON Schema features
%{
  "type" => "object",
  "properties" => %{...},
  "required" => [...],
  "additionalProperties" => true/false
}

# Arrays, nested objects, enums all supported
```

### Tool Not Found

**Problem:** `{:error, :method_not_found}`

**Solution:**
1. Verify tool exists: `{:ok, resp} = MyMCP.list_tools()`
2. Check tool name spelling
3. Ensure server has initialized properly

See **[REFERENCE.md](REFERENCE.md)** for complete troubleshooting guide.

## Performance Considerations

- **Tool caching** is enabled by default (discovery is expensive)
- **Timeouts** default to 30 seconds (configurable per tool)
- **Connection pooling** handled by Hermes transport layer
- **Memory usage** scales with number of pending requests

## Contributing

This library follows LangChain Elixir conventions:
- Ecto-style schemas and changesets
- Comprehensive documentation
- Type specs on public functions
- Test coverage with integration tests

## Resources

- **LangChain Elixir**: https://github.com/brainlid/langchain
- **Hermes MCP**: https://github.com/the-mikedavis/hermes
- **MCP Specification**: https://modelcontextprotocol.io/
- **MCP Servers**: https://github.com/modelcontextprotocol/servers

## License

Same as LangChain Elixir (MIT)

## Next Steps

- **New users**: Read [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)
- **API details**: See [API_REFERENCE.md](API_REFERENCE.md)
- **Architecture**: Review [ARCHITECTURE.md](ARCHITECTURE.md)
- **Testing**: Follow [TESTING.md](TESTING.md)

---

**Version:** 0.1.0
**Last Updated:** 2025-11-10
**Status:** Production Ready
