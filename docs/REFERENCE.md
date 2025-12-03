# LangChain MCP Reference

Technical reference for schemas, behaviors, and troubleshooting.

## Table of Contents

1. [JSON Schema Reference](#json-schema-reference)
2. [MCP Protocol Reference](#mcp-protocol-reference)
3. [Data Structure Reference](#data-structure-reference)
4. [Model-Specific Behaviors](#model-specific-behaviors)
5. [Error Code Reference](#error-code-reference)
6. [Configuration Reference](#configuration-reference)
7. [Troubleshooting Guide](#troubleshooting-guide)
8. [Performance Tuning](#performance-tuning)

## JSON Schema Reference

### Supported Types

| JSON Schema Type | LangChain Type | Elixir Type  | Notes               |
| ---------------- | -------------- | ------------ | ------------------- |
| `"string"`       | `:string`      | `String.t()` | Text data           |
| `"number"`       | `:number`      | `float()`    | Floating point      |
| `"integer"`      | `:integer`     | `integer()`  | Whole numbers       |
| `"boolean"`      | `:boolean`     | `boolean()`  | true/false          |
| `"array"`        | `:array`       | `list()`     | Lists/arrays        |
| `"object"`       | `:object`      | `map()`      | Nested objects      |
| `"null"`         | -              | `nil`        | Handled as optional |

### Supported Constraints

| Constraint             | Applies To     | Example                         | Handling              |
| ---------------------- | -------------- | ------------------------------- | --------------------- |
| `required`             | All types      | `"required": ["name"]`          | Sets `required: true` |
| `enum`                 | All types      | `"enum": ["a", "b"]`            | Sets `enum: [...]`    |
| `default`              | All types      | `"default": 10`                 | Preserved in param    |
| `minimum`              | number/integer | `"minimum": 0`                  | Added to description  |
| `maximum`              | number/integer | `"maximum": 100`                | Added to description  |
| `minLength`            | string         | `"minLength": 1`                | Added to description  |
| `maxLength`            | string         | `"maxLength": 255`              | Added to description  |
| `pattern`              | string         | `"pattern": "^[a-z]+$"`         | Added to description  |
| `minItems`             | array          | `"minItems": 1`                 | Added to description  |
| `maxItems`             | array          | `"maxItems": 10`                | Added to description  |
| `items`                | array          | `"items": {...}`                | Nested schema         |
| `properties`           | object         | `"properties": {...}`           | Nested properties     |
| `additionalProperties` | object         | `"additionalProperties": false` | Validation hint       |

### Complete Schema Examples

#### Simple String Parameter

```json
{
  "type": "object",
  "properties": {
    "name": {
      "type": "string",
      "description": "User's full name",
      "minLength": 1,
      "maxLength": 100
    }
  },
  "required": ["name"]
}
```

Converts to:

```elixir
[
  %FunctionParam{
    name: "name",
    type: :string,
    description: "User's full name. Must be >= 1 and <= 100 characters.",
    required: true
  }
]
```

#### Enum Parameter

```json
{
  "type": "object",
  "properties": {
    "status": {
      "type": "string",
      "enum": ["pending", "approved", "rejected"],
      "description": "Request status"
    }
  }
}
```

Converts to:

```elixir
[
  %FunctionParam{
    name: "status",
    type: :string,
    enum: ["pending", "approved", "rejected"],
    description: "Request status",
    required: false
  }
]
```

#### Numeric Constraints

```json
{
  "type": "object",
  "properties": {
    "age": {
      "type": "integer",
      "minimum": 0,
      "maximum": 150
    },
    "score": {
      "type": "number",
      "minimum": 0.0,
      "maximum": 100.0
    }
  }
}
```

#### Array Parameter

```json
{
  "type": "object",
  "properties": {
    "tags": {
      "type": "array",
      "items": {
        "type": "string"
      },
      "minItems": 1,
      "maxItems": 10
    }
  }
}
```

#### Nested Object

```json
{
  "type": "object",
  "properties": {
    "user": {
      "type": "object",
      "properties": {
        "name": { "type": "string" },
        "email": { "type": "string" },
        "age": { "type": "integer" }
      },
      "required": ["name", "email"]
    }
  }
}
```

#### Complex Example

```json
{
  "type": "object",
  "properties": {
    "query": {
      "type": "string",
      "description": "Search query",
      "minLength": 1
    },
    "filters": {
      "type": "object",
      "properties": {
        "category": {
          "type": "string",
          "enum": ["electronics", "books", "clothing"]
        },
        "min_price": {
          "type": "number",
          "minimum": 0
        },
        "max_price": {
          "type": "number"
        }
      }
    },
    "sort": {
      "type": "string",
      "enum": ["relevance", "price_asc", "price_desc"],
      "default": "relevance"
    },
    "limit": {
      "type": "integer",
      "minimum": 1,
      "maximum": 100,
      "default": 10
    }
  },
  "required": ["query"]
}
```

## MCP Protocol Reference

### JSON-RPC 2.0 Format

All MCP messages use JSON-RPC 2.0:

#### Request

```json
{
  "jsonrpc": "2.0",
  "id": "unique-request-id",
  "method": "tools/call",
  "params": {
    "name": "tool_name",
    "arguments": {
      "arg1": "value1"
    }
  }
}
```

#### Response (Success)

```json
{
  "jsonrpc": "2.0",
  "id": "unique-request-id",
  "result": {
    "content": [{ "type": "text", "text": "Result" }],
    "isError": false
  }
}
```

#### Response (Error)

```json
{
  "jsonrpc": "2.0",
  "id": "unique-request-id",
  "error": {
    "code": -32601,
    "message": "Method not found",
    "data": {}
  }
}
```

### MCP Methods

| Method           | Purpose               | Params          | Returns          |
| ---------------- | --------------------- | --------------- | ---------------- |
| `initialize`     | Initialize connection | client info     | server info      |
| `tools/list`     | List available tools  | cursor          | tools array      |
| `tools/call`     | Execute tool          | name, arguments | result content   |
| `resources/list` | List resources        | cursor          | resources array  |
| `resources/read` | Read resource         | uri             | resource content |
| `prompts/list`   | List prompts          | cursor          | prompts array    |
| `prompts/get`    | Get prompt            | name, arguments | prompt messages  |
| `ping`           | Health check          | -               | empty result     |

### Content Types

#### Text Content

```json
{
  "type": "text",
  "text": "The content as a string"
}
```

#### Image Content

```json
{
  "type": "image",
  "data": "base64-encoded-image-data",
  "mimeType": "image/png"
}
```

#### Audio Content (Future)

```json
{
  "type": "audio",
  "data": "base64-encoded-audio-data",
  "mimeType": "audio/mp3"
}
```

#### Resource Reference

```json
{
  "type": "resource",
  "resource": {
    "uri": "file:///path/to/file",
    "mimeType": "text/plain"
  }
}
```

## Data Structure Reference

### Complete Type Definitions

```elixir
# LangChain.MCP.Adapter
@type t :: %__MODULE__{
  config: Config.t(),
  cached_tools: [map()] | nil
}

# LangChain.MCP.Config
@type t :: %__MODULE__{
  client: module(),
  fallback_client: module() | nil,
  cache: boolean(),
  timeout: pos_integer(),
  async: boolean(),
  filter: :only | :except | :none,
  filter_list: [String.t()],
  filter_fn: (map() -> boolean()) | nil,
  before_fallback: (term(), map() -> any()) | nil
}

# Anubis.MCP.Response
@type t :: %__MODULE__{
  result: map(),
  id: String.t(),
  is_error: boolean(),
  method: String.t() | nil
}

# Anubis.MCP.Error
@type t :: %__MODULE__{
  code: integer(),
  reason: atom(),
  message: String.t(),
  data: map()
}

# LangChain.Function
@type t :: %__MODULE__{
  name: String.t(),
  description: String.t(),
  parameters_schema: FunctionParam.t() | nil,
  parameters: [FunctionParam.t()],
  function: (map(), map() -> any())
}

# LangChain.FunctionParam
@type t :: %__MODULE__{
  name: String.t(),
  type: :string | :number | :integer | :boolean | :array | :object,
  description: String.t(),
  required: boolean(),
  enum: [any()] | nil,
  default: any() | nil
}

# LangChain.ContentPart
@type t :: %__MODULE__{
  type: :text | :image | :audio,
  content: String.t(),
  options: map()
}
```

## Model-Specific Behaviors

### Pre-filling Assistant Responses

**Claude (Anthropic):**

- ✅ Supports and encourages pre-filling
- Works well with XML tags
- Completes partial responses naturally

```elixir
messages = [
  Message.new_user!("Respond with <answer>YOUR ANSWER</answer>"),
  Message.new_assistant!("<answer>")  # Claude will complete with closing tag
]
```

**ChatGPT (OpenAI):**

- ⚠️ Limited support
- May not include closing tags
- Discouraged in API

```elixir
# Not recommended with ChatGPT
messages = [
  Message.new_user!("Respond with <answer>YOUR ANSWER</answer>"),
  Message.new_assistant!("<answer>")  # May not close tag properly
]
```

**Gemini (Google):**

- ⚠️ Not officially supported
- Results may vary

### Image Content Handling

**Claude (Anthropic):**

- ✅ Requires separate media type field
- ❌ Does NOT accept data URI format

```elixir
# Correct for Claude
ContentPart.image!("base64data...", media: "image/jpeg")

# Wrong for Claude
ContentPart.image!("data:image/jpeg;base64,base64data...")
```

**ChatGPT (OpenAI):**

- ✅ Requires data URI format
- Must include media type in data string

```elixir
# Correct for ChatGPT
ContentPart.image!("data:image/jpeg;base64,base64data...")

# Wrong for ChatGPT
ContentPart.image!("base64data...", media: "image/jpeg")
```

**Gemini (Google):**

- ✅ Supports both formats
- Prefers data URI format

### Token Usage Reporting

**ChatGPT & Claude & Bumblebee:**

- Return token usage at end of response
- Single usage report per message

**Gemini:**

- Returns token usage in each delta
- Cumulative count increments
- Final message has total

### Function Calling Differences

**Claude:**

- Native tool use via `tool_use` blocks
- Supports multiple tool calls in sequence
- Returns structured tool results

**ChatGPT:**

- Function calling via `function_call` field
- Parallel function calling supported
- Requires specific model versions (gpt-3.5-turbo-1106+)

**Gemini:**

- Function calling via `functionCall` field
- Similar to ChatGPT format
- Available in recent models

## Error Code Reference

### JSON-RPC Error Codes

| Code             | Name             | Meaning                | Retryable |
| ---------------- | ---------------- | ---------------------- | --------- |
| -32700           | Parse Error      | Invalid JSON           | No        |
| -32600           | Invalid Request  | Malformed request      | No        |
| -32601           | Method Not Found | Unknown method         | No        |
| -32602           | Invalid Params   | Bad parameters         | No        |
| -32603           | Internal Error   | Server error           | Yes       |
| -32000 to -32099 | Server Error     | Implementation-defined | Varies    |

### MCP-Specific Errors

| Code   | Reason                | Description            | Retryable |
| ------ | --------------------- | ---------------------- | --------- |
| -32000 | `:send_failure`       | Failed to send message | Yes       |
| -32001 | `:request_timeout`    | Request timed out      | Yes       |
| -32002 | `:connection_refused` | Server unavailable     | Yes       |
| -32003 | `:request_cancelled`  | Request cancelled      | No        |
| -32004 | `:connection_lost`    | Connection dropped     | Yes       |

### Domain Errors

Domain errors are returned in successful responses:

```elixir
%Response{
  is_error: true,
  result: %{
    "isError" => true,
    "content" => [
      %{
        "type" => "text",
        "text" => "Tool execution failed: File not found"
      }
    ]
  }
}
```

**Not Retryable** - These are business logic errors.

### Error Handling Decision Tree

```
Error occurs
    │
    ▼
Is it a Response with is_error: true?
    │
    ├─ Yes → Domain error (not retryable)
    │          Return error to user
    │
    └─ No → Is it a %Anubis.MCP.Error{}?
            │
            ├─ Yes → Check error code
            │          │
            │          ├─ -32603 or -32000-32099?
            │          │   └─ Yes → Transient (retryable)
            │          │
            │          └─ -32600, -32601, -32602?
            │              └─ No → Permanent (not retryable)
            │
            └─ No → Unknown error
                     Log and treat as not retryable
```

## Configuration Reference

### Adapter Configuration

```elixir
%Config{
  # Required
  client: MyApp.MCP,                    # Anubis client module

  # Optional - Resilience
  fallback_client: MyApp.BackupMCP,     # Fallback client
  before_fallback: fn error, context -> # Callback before fallback
    Logger.warning("Fallback: #{inspect(error)}")
  end,

  # Optional - Performance
  cache: true,                          # Cache tool discovery
  timeout: 30_000,                      # Request timeout (ms)
  async: true,                          # Async execution

  # Optional - Filtering
  filter: :only,                        # :only | :except | :none
  filter_list: ["safe_tool"],           # Tool names
  filter_fn: fn tool ->                 # Custom filter
    String.starts_with?(tool["name"], "safe_")
  end
}
```

### Anubis Client Configuration

```elixir
defmodule MyApp.MCP do
  use Anubis.Client,
    # Required
    name: "MyApp",
    version: "1.0.0",
    protocol_version: "2025-03-26",

    # Optional
    capabilities: [
      :roots,                           # Root directory support
      {:sampling, list_changed?: true}  # LLM sampling with callbacks
    ]
end

# Start with options
{:ok, _pid} = MyApp.MCP.start_link(
  transport: {:streamable_http, base_url: "http://localhost:5000"},
  name: :my_mcp_client
)
```

### Transport Configuration

#### STDIO (Subprocess)

```elixir
{:stdio,
  command: "npx",
  args: ["@modelcontextprotocol/server-filesystem", "/path"],
  env: %{"DEBUG" => "1"}  # Optional environment variables
}
```

#### Streamable HTTP

```elixir
{:streamable_http,
  base_url: "http://localhost:5000",
  headers: %{"Authorization" => "Bearer token"}  # Optional headers
}
```

#### Server-Sent Events

```elixir
{:sse,
  base_url: "http://localhost:8000",
  endpoint: "/mcp"  # Optional custom endpoint
}
```

#### WebSocket

```elixir
{:websocket,
  url: "ws://localhost:8000/mcp",
  headers: %{"Authorization" => "Bearer token"}
}
```

## Troubleshooting Guide

### Connection Issues

#### ECONNREFUSED

**Symptoms:**

- `{:error, :econnrefused}`
- Can't connect to MCP server

**Diagnosis:**

```bash
# Check if server is running
curl http://localhost:5000/health

# Check port
lsof -i :5000

# Check firewall
sudo iptables -L
```

**Solutions:**

1. Start MCP server
2. Verify correct URL/port
3. Check firewall rules
4. Ensure server is listening on correct interface (0.0.0.0 vs 127.0.0.1)

#### Connection Timeout

**Symptoms:**

- `{:error, :request_timeout}`
- Long delays before failure

**Diagnosis:**

```elixir
# Test with longer timeout
{:ok, adapter} = Adapter.new(
  client: MyApp.MCP,
  timeout: 120_000  # 2 minutes
)
```

**Solutions:**

1. Increase timeout value
2. Check network latency: `ping server-host`
3. Verify server is responsive
4. Consider using fallback

### Tool Discovery Issues

#### No Tools Found

**Symptoms:**

- `Adapter.to_functions(adapter)` returns `[]`
- Tools expected but not available

**Diagnosis:**

```elixir
# Check raw response
{:ok, response} = Anubis.Client.list_tools(MyApp.MCP)
IO.inspect(response.result)
```

**Solutions:**

1. Verify server has tools configured
2. Check server logs for errors
3. Ensure server is initialized properly
4. Try force refresh: `Adapter.to_functions(adapter, force_refresh: true)`

#### Wrong Tools Returned

**Symptoms:**

- Unexpected tools in list
- Expected tools missing

**Diagnosis:**

```elixir
# Check filter configuration
{:ok, adapter} = Adapter.new(
  client: MyApp.MCP,
  filter: :only,
  filter_list: ["expected_tool"]
)

# Debug filter function
{:ok, adapter} = Adapter.new(
  client: MyApp.MCP,
  filter_fn: fn tool ->
    IO.inspect(tool, label: "Checking tool")
    # your filter logic
  end
)
```

**Solutions:**

1. Verify filter configuration
2. Check tool names for typos
3. Test filter function logic
4. Disable filtering temporarily to see all tools

### Tool Execution Issues

#### Method Not Found

**Symptoms:**

- `{:error, :method_not_found}`
- Tool exists but can't be called

**Diagnosis:**

```elixir
# List tools
{:ok, response} = Anubis.Client.list_tools(MyApp.MCP)
tools = response.result["tools"]
tool_names = Enum.map(tools, & &1["name"])
IO.inspect(tool_names, label: "Available tools")

# Try calling
{:ok, response} = Anubis.Client.call_tool(MyApp.MCP, "tool_name", %{})
```

**Solutions:**

1. Verify exact tool name (case-sensitive)
2. Ensure tool is enabled on server
3. Check server logs
4. Refresh tool cache

#### Invalid Parameters

**Symptoms:**

- `{:error, :invalid_params}`
- Parameters rejected

**Diagnosis:**

```elixir
# Check parameter schema
tools = Adapter.to_functions(adapter)
tool = Enum.find(tools, &(&1.name == "problematic_tool"))
IO.inspect(tool.parameters, label: "Expected parameters")

# Try with explicit types
{:ok, response} = Anubis.Client.call_tool(
  MyApp.MCP,
  "tool_name",
  %{"count" => 5}  # integer, not "5" string
)
```

**Solutions:**

1. Verify parameter types match schema
2. Ensure all required parameters provided
3. Check parameter names (case-sensitive)
4. Validate parameter format (e.g., dates, URIs)

### Performance Issues

#### Slow Tool Discovery

**Symptoms:**

- First `to_functions` call takes seconds
- Repeated calls still slow

**Diagnosis:**

```elixir
# Time the call
{time_us, result} = :timer.tc(fn ->
  Adapter.to_functions(adapter)
end)
IO.puts("Tool discovery took #{time_us / 1_000}ms")

# Check if caching is enabled
IO.inspect(adapter.config.cache, label: "Cache enabled?")
```

**Solutions:**

1. Enable caching: `cache: true`
2. Pre-warm cache at startup
3. Check server performance
4. Consider caching at application level

#### Slow Tool Execution

**Symptoms:**

- Tool calls take too long
- Timeouts occurring

**Diagnosis:**

```elixir
# Profile tool execution
{time_us, result} = :timer.tc(fn ->
  ToolExecutor.execute_tool(config, "slow_tool", %{})
end)
IO.puts("Tool execution took #{time_us / 1_000}ms")
```

**Solutions:**

1. Increase timeout if appropriate
2. Optimize server-side tool implementation
3. Use async execution if possible
4. Consider tool caching for idempotent operations

### Error Handling Issues

#### Fallback Not Working

**Symptoms:**

- Primary fails but fallback not used
- Both clients fail

**Diagnosis:**

```elixir
# Test error classification
error = ... # your error
{type, retryable, msg} = ErrorHandler.classify_error(error)
IO.puts("Type: #{type}, Retryable: #{retryable}")

# Test fallback callback
{:ok, adapter} = Adapter.new(
  client: MyApp.Primary,
  fallback_client: MyApp.Fallback,
  before_fallback: fn error, context ->
    IO.puts("FALLBACK TRIGGERED!")
    IO.inspect(error, label: "Error")
    IO.inspect(context, label: "Context")
  end
)
```

**Solutions:**

1. Verify fallback client is running
2. Ensure error is retryable (not domain error)
3. Check fallback client configuration
4. Verify `before_fallback` callback doesn't raise

#### Domain Errors Triggering Fallback

**Symptoms:**

- Tool errors causing unexpected fallbacks
- Fallback called for business logic errors

**Diagnosis:**

```elixir
# Check error type
error = %Response{is_error: true, result: %{...}}
{type, retryable, _} = ErrorHandler.classify_error(error)
IO.puts("Domain error should not retry: #{retryable}")
```

**Solutions:**

1. Handle domain errors separately
2. Don't configure fallback for domain errors
3. Check tool implementation
4. Return proper error responses from tools

## Performance Tuning

### Connection Pooling

**For HTTP Transports:**

- Anubis uses HTTP client connection pooling automatically
- No additional configuration needed
- Reuses connections for multiple requests

**For STDIO Transports:**

- Each client maintains single subprocess
- Consider multiple clients for parallelism
- Balance between resource usage and concurrency

### Request Parallelism

```elixir
# Sequential (slow)
result1 = call_tool("tool1", %{})
result2 = call_tool("tool2", %{})
result3 = call_tool("tool3", %{})

# Parallel (fast)
tasks = [
  Task.async(fn -> call_tool("tool1", %{}) end),
  Task.async(fn -> call_tool("tool2", %{}) end),
  Task.async(fn -> call_tool("tool3", %{}) end)
]
results = Task.await_many(tasks, timeout: 60_000)
```

### Caching Strategies

```elixir
# Tool discovery caching (built-in)
{:ok, adapter} = Adapter.new(client: MyApp.MCP, cache: true)

# Tool result caching (custom)
defmodule MyApp.ToolCache do
  use GenServer

  # Implement result caching for expensive tools
  # TTL-based expiration
  # Cache invalidation on updates
end
```

### Memory Optimization

```elixir
# For large tool results, stream instead of loading fully
# Use async: true for non-blocking execution
# Clear tool cache when not needed
{:ok, adapter} = Adapter.new(client: MyApp.MCP, cache: false)
```

### Timeout Tuning

```elixir
# Fast operations
{:ok, adapter} = Adapter.new(
  client: MyApp.FastMCP,
  timeout: 5_000  # 5 seconds
)

# Slow operations (data processing, ML inference)
{:ok, adapter} = Adapter.new(
  client: MyApp.SlowMCP,
  timeout: 300_000  # 5 minutes
)

# Per-operation timeout (if supported by server)
# Some MCP servers respect timeout hints in requests
```

---

## Additional Resources

- **MCP Specification:** https://modelcontextprotocol.io/
- **JSON Schema Spec:** https://json-schema.org/
- **JSON-RPC 2.0 Spec:** https://www.jsonrpc.org/specification
- **Anubis Documentation:** https://hexdocs.pm/anubis_mcp/
- **LangChain Documentation:** https://hexdocs.pm/langchain/

---

**Last Updated:** 2025-11-10
