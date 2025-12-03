# LangChain MCP Integration Guide

Practical guide for integrating MCP tools into your LangChain applications.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Basic Integration](#basic-integration)
3. [Advanced Configuration](#advanced-configuration)
4. [Real-World Examples](#real-world-examples)
5. [Common Patterns](#common-patterns)
6. [Best Practices](#best-practices)
7. [Troubleshooting](#troubleshooting)

## Getting Started

### Installation

Add to your `mix.exs`:

```elixir
defp deps do
  [
    {:langchain, "~> 0.4"},
    {:langchain_mcp, "~> 0.1.0"},
    {:anubis_mcp, "~> 0.16.0"}
  ]
end
```

Run:
```bash
mix deps.get
```

### Quick Start (5 Minutes)

Create a simple MCP integration:

```elixir
# 1. Define MCP client
defmodule MyApp.MCP do
  use LangChain.MCP.Client,
    name: "MyApp",
    version: "1.0.0",
    protocol_version: "2025-03-26"
end

# 2. Add to application supervision tree
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    {MyApp.MCP,
     transport: {:streamable_http, base_url: "http://localhost:5000"},
     name: :my_mcp}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end

# 3. Use in your code
{:ok, adapter} = LangChain.MCP.Adapter.new(client: MyApp.MCP)
tools = LangChain.MCP.Adapter.to_functions(adapter)

{:ok, chain} =
  LLMChain.new!(%{llm: ChatAnthropic.new!()})
  |> LLMChain.add_tools(tools)
  |> LLMChain.add_message(Message.new_user!("What time is it?"))
  |> LLMChain.run(mode: :while_needs_response)
```

## Basic Integration

### Step 1: Define Your MCP Client

```elixir
defmodule MyApp.GitHubMCP do
  use LangChain.MCP.Client,
    name: "MyApp-GitHub",
    version: "1.0.0",
    protocol_version: "2025-03-26",
    capabilities: []  # Optional: specify capabilities
end
```

**Naming Convention:**
- Use descriptive names: `GitHubMCP`, `FileSystemMCP`, `DatabaseMCP`
- Include context in name: "MyApp-GitHub" vs just "GitHub"

### Step 2: Configure Transport

Different transport options for different use cases:

#### HTTP Server (Most Common)

```elixir
{MyApp.GitHubMCP,
 transport: {:streamable_http, base_url: "http://localhost:3000"},
 name: :github_mcp}
```

**Use When:**
- MCP server is a web service
- Multiple clients need to connect
- Server runs independently

#### STDIO Process (CLI Tools)

```elixir
{MyApp.FileSystemMCP,
 transport: {:stdio,
   command: "npx",
   args: ["@modelcontextprotocol/server-filesystem", "/home/user/documents"]
 },
 name: :fs_mcp}
```

**Use When:**
- MCP server is a CLI tool
- Need tight coupling with subprocess
- Server is stateless

#### WebSocket (Long-Lived Connections)

```elixir
{MyApp.ChatMCP,
 transport: {:websocket, url: "ws://localhost:8000/mcp"},
 name: :chat_mcp}
```

**Use When:**
- Need bidirectional communication
- Server sends notifications
- Long-lived connection preferred

### Step 3: Create Adapter

```elixir
# Basic adapter
{:ok, adapter} = LangChain.MCP.Adapter.new(client: MyApp.GitHubMCP)

# Adapter with options
{:ok, adapter} = LangChain.MCP.Adapter.new(
  client: MyApp.GitHubMCP,
  cache: true,              # Cache tool discovery
  timeout: 30_000,          # 30 second timeout
  filter: :only,            # Only include specific tools
  filter_list: ["create_issue", "search_issues"]
)
```

### Step 4: Discover Tools

```elixir
# Get all tools as LangChain Functions
tools = LangChain.MCP.Adapter.to_functions(adapter)

# Inspect what's available
Enum.each(tools, fn tool ->
  IO.puts("Tool: #{tool.name} - #{tool.description}")
  IO.puts("  Parameters: #{length(tool.parameters)}")
end)
```

### Step 5: Use in LLMChain

```elixir
# Create chain with MCP tools
{:ok, chain} =
  LLMChain.new!(%{
    llm: ChatAnthropic.new!(%{
      model: "claude-3-5-sonnet-20241022",
      api_key: System.get_env("ANTHROPIC_API_KEY")
    })
  })
  |> LLMChain.add_tools(tools)
  |> LLMChain.add_message(Message.new_user!("Create a GitHub issue titled 'Test Issue'"))
  |> LLMChain.run(mode: :while_needs_response)

# Get final response
final_message = List.last(chain.messages)
IO.puts(final_message.content)
```

## Advanced Configuration

### Tool Filtering

#### Include Only Specific Tools

```elixir
{:ok, adapter} = Adapter.new(
  client: MyApp.GitHubMCP,
  filter: :only,
  filter_list: ["create_issue", "add_comment", "close_issue"]
)
```

**Use Case:** Restrict agent to safe operations only

#### Exclude Dangerous Tools

```elixir
{:ok, adapter} = Adapter.new(
  client: MyApp.GitHubMCP,
  filter: :except,
  filter_list: ["delete_repo", "force_push", "revoke_access"]
)
```

**Use Case:** Allow all tools except potentially dangerous ones

#### Custom Filter Function

```elixir
{:ok, adapter} = Adapter.new(
  client: MyApp.GitHubMCP,
  filter_fn: fn tool ->
    # Only allow read-only operations
    tool["name"]
    |> String.starts_with?(["get_", "list_", "search_", "read_"])
  end
)
```

**Use Case:** Complex filtering logic based on tool metadata

### Fallback Configuration

```elixir
{:ok, adapter} = Adapter.new(
  client: MyApp.PrimaryGitHubMCP,
  fallback_client: MyApp.BackupGitHubMCP,
  before_fallback: fn error, context ->
    # Log to monitoring service
    Logger.error("Primary MCP failed, using fallback",
      error: inspect(error),
      context: inspect(context)
    )

    # Send alert
    MyApp.Alerts.send("MCP fallback triggered", %{
      primary: MyApp.PrimaryGitHubMCP,
      error: error
    })

    # Record metrics
    MyApp.Metrics.increment("mcp.fallback.triggered")
  end
)
```

**Use Case:** High availability production systems

### Caching Strategy

```elixir
# Enable caching (default)
{:ok, adapter} = Adapter.new(client: MyApp.MCP, cache: true)
tools = Adapter.to_functions(adapter)  # Fetches from server
tools = Adapter.to_functions(adapter)  # Uses cache

# Force refresh
tools = Adapter.to_functions(adapter, force_refresh: true)

# Disable caching
{:ok, adapter} = Adapter.new(client: MyApp.MCP, cache: false)
tools = Adapter.to_functions(adapter)  # Always fetches

# Manual cache refresh
{:ok, fresh_tools} = Adapter.refresh_tools(adapter)
```

**Recommendations:**
- Enable caching for production (tools rarely change)
- Disable for development (tools may change frequently)
- Use `force_refresh` after deploying new server version

### Timeout Configuration

```elixir
# Per-adapter timeout
{:ok, adapter} = Adapter.new(
  client: MyApp.MCP,
  timeout: 60_000  # 60 seconds for slow operations
)

# Different timeouts for different servers
{:ok, fast_adapter} = Adapter.new(
  client: MyApp.FastMCP,
  timeout: 5_000  # 5 seconds
)

{:ok, slow_adapter} = Adapter.new(
  client: MyApp.SlowMCP,
  timeout: 120_000  # 2 minutes
)
```

**Considerations:**
- Network latency
- Tool execution time
- Server processing time
- Balance between responsiveness and reliability

## Real-World Examples

### Example 1: GitHub Integration

Complete GitHub automation agent:

```elixir
defmodule MyApp.GitHubAgent do
  alias LangChain.{LLMChain, Message, ChatModels.ChatAnthropic}
  alias LangChain.MCP.Adapter

  def create_and_manage_issue(title, description) do
    # 1. Setup
    {:ok, adapter} = Adapter.new(
      client: MyApp.GitHubMCP,
      filter: :only,
      filter_list: [
        "create_issue",
        "add_label",
        "add_comment",
        "assign_user"
      ]
    )

    tools = Adapter.to_functions(adapter)

    # 2. Create chain
    {:ok, chain} =
      LLMChain.new!(%{
        llm: ChatAnthropic.new!(%{model: "claude-3-5-sonnet-20241022"})
      })
      |> LLMChain.add_tools(tools)
      |> LLMChain.add_message(
        Message.new_system!("""
        You are a GitHub automation assistant. Create issues, add labels,
        and manage tickets according to user requests.
        """)
      )
      |> LLMChain.add_message(
        Message.new_user!("""
        Create a new issue titled "#{title}" with description:
        #{description}

        Then add labels: bug, high-priority
        Finally, assign it to user "john-doe"
        """)
      )
      |> LLMChain.run(mode: :while_needs_response)

    # 3. Extract results
    final_message = List.last(chain.messages)
    {:ok, final_message.content}
  end
end

# Usage
{:ok, result} = MyApp.GitHubAgent.create_and_manage_issue(
  "Login page broken",
  "Users cannot login with valid credentials"
)
IO.puts(result)
# "I've created issue #42, added the labels, and assigned it to john-doe"
```

### Example 2: Multi-Server Integration

Combine tools from multiple MCP servers:

```elixir
defmodule MyApp.MultiToolAgent do
  def setup_tools do
    # GitHub tools
    {:ok, github_adapter} = Adapter.new(client: MyApp.GitHubMCP)
    github_tools = Adapter.to_functions(github_adapter)

    # Filesystem tools
    {:ok, fs_adapter} = Adapter.new(
      client: MyApp.FileSystemMCP,
      filter: :only,
      filter_list: ["read_file", "list_directory"]
    )
    fs_tools = Adapter.to_functions(fs_adapter)

    # Database tools
    {:ok, db_adapter} = Adapter.new(
      client: MyApp.DatabaseMCP,
      filter_fn: fn tool ->
        # Only allow SELECT queries
        String.contains?(tool["description"], "SELECT")
      end
    )
    db_tools = Adapter.to_functions(db_adapter)

    # Custom application tools
    custom_tools = [
      Function.new!(%{
        name: "send_email",
        description: "Send email notification",
        parameters: [
          FunctionParam.new!(%{name: "to", type: :string, required: true}),
          FunctionParam.new!(%{name: "subject", type: :string, required: true}),
          FunctionParam.new!(%{name: "body", type: :string, required: true})
        ],
        function: fn args, _context ->
          MyApp.Email.send(args["to"], args["subject"], args["body"])
        end
      })
    ]

    # Combine all tools
    github_tools ++ fs_tools ++ db_tools ++ custom_tools
  end

  def run_complex_task(user_request) do
    tools = setup_tools()

    {:ok, chain} =
      LLMChain.new!(%{llm: ChatAnthropic.new!()})
      |> LLMChain.add_tools(tools)
      |> LLMChain.add_message(
        Message.new_system!("""
        You have access to GitHub, filesystem, database, and email tools.
        Use them as needed to complete user requests.
        """)
      )
      |> LLMChain.add_message(Message.new_user!(user_request))
      |> LLMChain.run(mode: :while_needs_response)

    {:ok, List.last(chain.messages).content}
  end
end

# Usage
{:ok, result} = MyApp.MultiToolAgent.run_complex_task("""
Read the latest error log from /var/log/app.log,
query the database for affected users,
create a GitHub issue with details,
and send an email notification to the team.
""")
```

### Example 3: Streaming with Progress

Handle long-running operations with streaming:

```elixir
defmodule MyApp.StreamingAgent do
  def run_with_streaming(request) do
    {:ok, adapter} = Adapter.new(client: MyApp.MCP)
    tools = Adapter.to_functions(adapter)

    # Setup streaming callback
    callback = fn
      %{type: :tool_call, content: tool_call} ->
        IO.puts("🔧 Calling tool: #{tool_call.name}")

      %{type: :tool_result, content: result} ->
        IO.puts("✅ Tool completed")

      %{type: :message_delta, content: delta} ->
        IO.write(delta.content)

      %{type: :message_complete, content: message} ->
        IO.puts("\n✨ Response complete")
    end

    {:ok, chain} =
      LLMChain.new!(%{
        llm: ChatAnthropic.new!(%{stream: true}),
        callbacks: [callback]
      })
      |> LLMChain.add_tools(tools)
      |> LLMChain.add_message(Message.new_user!(request))
      |> LLMChain.run(mode: :while_needs_response)

    {:ok, chain}
  end
end
```

### Example 4: Error Handling and Retry

Robust error handling with fallback:

```elixir
defmodule MyApp.RobustAgent do
  require Logger

  def safe_tool_execution(tool_name, arguments) do
    {:ok, adapter} = Adapter.new(
      client: MyApp.PrimaryMCP,
      fallback_client: MyApp.BackupMCP,
      timeout: 30_000,
      before_fallback: &log_fallback/2
    )

    tools = Adapter.to_functions(adapter)
    tool = Enum.find(tools, &(&1.name == tool_name))

    if tool do
      execute_with_retry(tool, arguments)
    else
      {:error, :tool_not_found}
    end
  end

  defp execute_with_retry(tool, arguments, attempts \\ 3) do
    case tool.function.(arguments, %{}) do
      {:ok, result} ->
        {:ok, result}

      {:error, error} when attempts > 1 ->
        Logger.warning("Tool execution failed, retrying... (#{attempts - 1} left)")
        :timer.sleep(1000)  # Exponential backoff
        execute_with_retry(tool, arguments, attempts - 1)

      {:error, error} ->
        Logger.error("Tool execution failed after all retries: #{inspect(error)}")
        {:error, error}
    end
  end

  defp log_fallback(error, context) do
    Logger.warning("Fallback triggered",
      error: inspect(error),
      context: inspect(context),
      timestamp: DateTime.utc_now()
    )
  end
end
```

## Common Patterns

### Pattern 1: Tool Validation

Validate tool availability before using:

```elixir
def ensure_tools_available(adapter, required_tools) do
  available_tools =
    Adapter.to_functions(adapter)
    |> Enum.map(& &1.name)
    |> MapSet.new()

  required_set = MapSet.new(required_tools)
  missing = MapSet.difference(required_set, available_tools)

  if MapSet.size(missing) > 0 do
    {:error, {:missing_tools, MapSet.to_list(missing)}}
  else
    :ok
  end
end

# Usage
case ensure_tools_available(adapter, ["search", "create_issue"]) do
  :ok ->
    # Proceed with operations
    run_agent(adapter)

  {:error, {:missing_tools, missing}} ->
    Logger.error("Required tools not available: #{inspect(missing)}")
    {:error, :tools_unavailable}
end
```

### Pattern 2: Conditional Tool Loading

Load different tools based on environment:

```elixir
def get_tools_for_environment do
  env = Application.get_env(:my_app, :env)

  base_adapter = Adapter.new!(client: MyApp.MCP)

  case env do
    :prod ->
      # Production: restricted tools only
      Adapter.new!(
        client: MyApp.ProdMCP,
        filter: :only,
        filter_list: ["read_", "list_", "search_"]
      )

    :staging ->
      # Staging: most tools
      Adapter.new!(
        client: MyApp.StagingMCP,
        filter: :except,
        filter_list: ["delete_", "destroy_"]
      )

    :dev ->
      # Development: all tools
      Adapter.new!(client: MyApp.DevMCP)
  end
  |> Adapter.to_functions()
end
```

### Pattern 3: Tool Result Caching

Cache expensive tool results:

```elixir
defmodule MyApp.CachedToolExecutor do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def execute_cached(tool_name, arguments, ttl_seconds \\ 300) do
    cache_key = {tool_name, arguments}

    case GenServer.call(__MODULE__, {:get, cache_key}) do
      {:ok, result} ->
        {:ok, result, :cached}

      :miss ->
        # Execute tool
        result = execute_tool(tool_name, arguments)

        # Cache result
        GenServer.cast(__MODULE__, {:put, cache_key, result, ttl_seconds})

        {:ok, result, :fresh}
    end
  end

  # GenServer implementation...
end
```

### Pattern 4: Parallel Tool Execution

Execute multiple tools concurrently:

```elixir
def execute_tools_parallel(tool_calls) do
  tasks = Enum.map(tool_calls, fn {tool_name, args} ->
    Task.async(fn ->
      case execute_tool(tool_name, args) do
        {:ok, result} -> {tool_name, :ok, result}
        {:error, error} -> {tool_name, :error, error}
      end
    end)
  end)

  results = Task.await_many(tasks, timeout: 60_000)

  # Separate successes and failures
  {successes, failures} = Enum.split_with(results, fn
    {_, :ok, _} -> true
    {_, :error, _} -> false
  end)

  %{
    successes: Enum.map(successes, fn {name, :ok, result} -> {name, result} end),
    failures: Enum.map(failures, fn {name, :error, error} -> {name, error} end)
  }
end
```

## Best Practices

### 1. Client Lifecycle Management

**DO:**
- Start MCP clients in supervision tree
- Use named processes for easy access
- Handle client crashes gracefully

**DON'T:**
- Start clients in request handlers
- Start multiple clients to same server
- Ignore client failures

```elixir
# GOOD: Supervised client
children = [
  {MyApp.GitHubMCP,
   transport: {:streamable_http, base_url: "http://localhost:3000"},
   name: :github_mcp}
]

# BAD: Ad-hoc client
def handle_request(conn, _params) do
  {:ok, client} = MyApp.GitHubMCP.start_link(...)  # ❌ Wrong!
end
```

### 2. Tool Discovery

**DO:**
- Enable caching in production
- Validate required tools on startup
- Handle missing tools gracefully

**DON'T:**
- Discover tools on every request
- Assume tools are always available
- Ignore discovery errors

```elixir
# GOOD: Cache and validate
{:ok, adapter} = Adapter.new(client: MyApp.MCP, cache: true)
tools = Adapter.to_functions(adapter)

case validate_required_tools(tools) do
  :ok -> :ok
  {:error, missing} ->
    Logger.error("Missing required tools: #{inspect(missing)}")
    raise "Cannot start without required tools"
end

# BAD: Repeated discovery
def handle_request(conn, _params) do
  tools = Adapter.to_functions(adapter)  # ❌ Expensive!
end
```

### 3. Error Handling

**DO:**
- Classify errors appropriately
- Log errors with context
- Provide fallback behavior
- Return user-friendly messages

**DON'T:**
- Ignore errors
- Retry domain errors
- Expose internal error details to users

```elixir
# GOOD: Proper error handling
case ToolExecutor.execute_tool(config, tool_name, args) do
  {:ok, result} ->
    {:ok, result}

  {:error, error} ->
    {type, retryable, msg} = ErrorHandler.classify_error(error)
    Logger.error("Tool execution failed",
      type: type,
      retryable: retryable,
      error: inspect(error)
    )
    {:error, "Tool unavailable. Please try again later."}
end

# BAD: Silent failure
case ToolExecutor.execute_tool(config, tool_name, args) do
  {:ok, result} -> {:ok, result}
  _ -> {:ok, ""}  # ❌ Lost error information!
end
```

### 4. Security

**DO:**
- Filter tools based on user permissions
- Validate tool arguments
- Sanitize tool outputs
- Use separate MCP clients for different security contexts

**DON'T:**
- Expose all tools to all users
- Trust tool outputs blindly
- Log sensitive information

```elixir
# GOOD: Permission-based filtering
def get_tools_for_user(user) do
  filter_fn = fn tool ->
    user_can_use_tool?(user, tool["name"])
  end

  {:ok, adapter} = Adapter.new(
    client: MyApp.MCP,
    filter_fn: filter_fn
  )

  Adapter.to_functions(adapter)
end

# BAD: Unrestricted access
def get_tools_for_user(_user) do
  {:ok, adapter} = Adapter.new(client: MyApp.MCP)
  Adapter.to_functions(adapter)  # ❌ All users get all tools!
end
```

### 5. Testing

**DO:**
- Mock MCP clients in tests
- Test error paths
- Use integration tests with test server
- Test timeout scenarios

**DON'T:**
- Depend on external servers in unit tests
- Skip error case testing
- Test only happy paths

See [TESTING.md](TESTING.md) for detailed testing guide.

### 6. Monitoring

**DO:**
- Track tool execution time
- Monitor fallback usage
- Log tool failures
- Alert on repeated failures

**DON'T:**
- Ignore performance degradation
- Miss fallback events
- Let errors accumulate silently

```elixir
def execute_with_telemetry(tool_name, args) do
  start_time = System.monotonic_time(:millisecond)

  result = ToolExecutor.execute_tool(config, tool_name, args)

  duration = System.monotonic_time(:millisecond) - start_time

  :telemetry.execute(
    [:my_app, :mcp, :tool, :execute],
    %{duration: duration},
    %{tool: tool_name, success: match?({:ok, _}, result)}
  )

  result
end
```

## Troubleshooting

### Issue: Connection Refused

**Symptom:** `{:error, :econnrefused}`

**Solutions:**
1. Verify MCP server is running
2. Check URL/port configuration
3. Verify network connectivity
4. Check firewall rules

```bash
# Test server connectivity
curl http://localhost:3000/health

# Check port
lsof -i :3000
```

### Issue: Tool Not Found

**Symptom:** `{:error, :method_not_found}`

**Solutions:**
1. Verify tool name spelling
2. Check tool is in filter list (if filtering)
3. Refresh tool cache
4. Verify server supports tool

```elixir
# Debug: List available tools
{:ok, adapter} = Adapter.new(client: MyApp.MCP)
tools = Adapter.to_functions(adapter)
Enum.each(tools, &IO.puts(&1.name))
```

### Issue: Timeout Errors

**Symptom:** `{:error, :request_timeout}`

**Solutions:**
1. Increase timeout value
2. Check server performance
3. Verify network latency
4. Consider async execution

```elixir
# Increase timeout
{:ok, adapter} = Adapter.new(
  client: MyApp.MCP,
  timeout: 120_000  # 2 minutes
)
```

### Issue: Invalid Parameters

**Symptom:** `{:error, :invalid_params}`

**Solutions:**
1. Check parameter types match schema
2. Verify required parameters provided
3. Validate parameter format
4. Check for typos in parameter names

```elixir
# Debug: Print tool schema
tool = Enum.find(tools, &(&1.name == "problematic_tool"))
IO.inspect(tool.parameters, label: "Expected parameters")
```

### Issue: Fallback Not Triggering

**Symptom:** Primary failure but fallback not used

**Solutions:**
1. Verify fallback client configured
2. Check error is retryable (not domain error)
3. Ensure fallback client is running
4. Check `before_fallback` callback for errors

```elixir
# Debug: Test error classification
error = ...
{type, retryable, msg} = ErrorHandler.classify_error(error)
IO.puts("Type: #{type}, Retryable: #{retryable}")
```

### Issue: Cache Stale

**Symptom:** Old tools returned after server update

**Solutions:**
1. Force refresh cache
2. Restart application
3. Disable caching during development

```elixir
# Force refresh
{:ok, fresh_tools} = Adapter.refresh_tools(adapter)
tools = Adapter.to_functions(adapter, force_refresh: true)
```

---

## Next Steps

- **Testing:** See [TESTING.md](TESTING.md) for testing guide
- **API Details:** See [API_REFERENCE.md](API_REFERENCE.md) for complete API
- **Architecture:** See [ARCHITECTURE.md](ARCHITECTURE.md) for system design
- **Reference:** See [REFERENCE.md](REFERENCE.md) for schemas and troubleshooting

---

**Last Updated:** 2025-11-10
