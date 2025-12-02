# LangChain MCP Architecture

Complete architectural overview of the LangChain MCP integration, including Anubis client layer and LangChain adapter implementation.

## Table of Contents

1. [System Overview](#system-overview)
2. [Component Architecture](#component-architecture)
3. [Data Flow](#data-flow)
4. [Module Design](#module-design)
5. [Error Handling Strategy](#error-handling-strategy)
6. [State Management](#state-management)
7. [Performance Considerations](#performance-considerations)
8. [Design Decisions](#design-decisions)

## System Overview

The LangChain MCP integration consists of three layers:

```
┌─────────────────────────────────────────────────────────────┐
│                    LangChain Application                     │
│  • LLMChain orchestration                                    │
│  • Message management                                        │
│  • Function calling                                          │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│             LangChain MCP Adapter Layer                      │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  LangChain.MCP.Adapter                                │  │
│  │  • Tool discovery                                     │  │
│  │  • Caching                                            │  │
│  │  • Filtering                                          │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │                                            │
│  ┌──────────────▼───────────────────────────────────────┐  │
│  │  LangChain.MCP.SchemaConverter                        │  │
│  │  • JSON Schema → FunctionParam                        │  │
│  │  • Type mapping                                       │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │                                            │
│  ┌──────────────▼───────────────────────────────────────┐  │
│  │  LangChain.MCP.ToolExecutor                           │  │
│  │  • Tool invocation                                    │  │
│  │  • Fallback logic                                     │  │
│  │  • Result conversion                                  │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │                                            │
│  ┌──────────────▼───────────────────────────────────────┐  │
│  │  LangChain.MCP.ContentMapper                          │  │
│  │  • MCP content → ContentParts                         │  │
│  │  • Multi-modal support                                │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │                                            │
│  ┌──────────────▼───────────────────────────────────────┐  │
│  │  LangChain.MCP.ErrorHandler                           │  │
│  │  • Error classification                               │  │
│  │  • Retry determination                                │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│                    Anubis Client Layer                       │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Anubis.Client (DSL-Generated API)                    │  │
│  │  • list_tools()                                       │  │
│  │  • call_tool(name, args)                              │  │
│  │  • list_resources()                                   │  │
│  │  • get_prompt()                                       │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │                                            │
│  ┌──────────────▼───────────────────────────────────────┐  │
│  │  Anubis.Client.Base (GenServer)                       │  │
│  │  • Request lifecycle management                       │  │
│  │  • State tracking                                     │  │
│  │  • Timeout handling                                   │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │                                            │
│  ┌──────────────▼───────────────────────────────────────┐  │
│  │  Anubis.MCP.Message                                   │  │
│  │  • JSON-RPC encoding/decoding                         │  │
│  │  • Protocol compliance                                │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│                   Transport Layer                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │    STDIO     │  │     HTTP     │  │   WebSocket  │     │
│  │  (Process)   │  │    (SSE)     │  │   (Network)  │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
        ┌────────────────────┐
        │   MCP Server        │
        │  (External)         │
        └────────────────────┘
```

## Component Architecture

### LangChain MCP Adapter Layer

#### 1. LangChain.MCP.Adapter

**Purpose:** Main public API for MCP integration

**Responsibilities:**

- Tool discovery from MCP servers
- Tool caching management
- Tool filtering (only/except/custom)
- Configuration validation

**Key Functions:**

```elixir
# Create adapter with configuration
new(opts) :: {:ok, %Adapter{}} | {:error, term()}

# Discover and convert tools to LangChain Functions
to_functions(adapter, opts \\ []) :: [%Function{}]

# Refresh tool cache
refresh_tools(adapter) :: {:ok, [map()]} | {:error, term()}
```

**State:**

```elixir
%Adapter{
  config: %Config{},
  cached_tools: [map()] | nil
}
```

#### 2. LangChain.MCP.Config

**Purpose:** Configuration validation and storage

**Responsibilities:**

- Validate adapter configuration
- Store client references
- Manage fallback settings
- Handle callback configuration

**Schema:**

```elixir
embedded_schema do
  field :client, :any, virtual: true
  field :fallback_client, :any, virtual: true
  field :cache, :boolean, default: true
  field :timeout, :integer, default: 30_000
  field :async, :boolean, default: true
  field :filter, Ecto.Enum, values: [:only, :except, :none]
  field :filter_list, {:array, :string}, default: []
  field :filter_fn, :any, virtual: true
  field :before_fallback, :any, virtual: true
end
```

#### 3. LangChain.MCP.SchemaConverter

**Purpose:** Convert between JSON Schema and LangChain parameters

**Responsibilities:**

- Parse JSON Schema definitions
- Convert to FunctionParam structs
- Handle nested objects and arrays
- Support enums and type constraints

**Key Functions:**

```elixir
# Convert JSON Schema to FunctionParam list
convert_input_schema(schema) :: [%FunctionParam{}]

# Convert FunctionParam back to JSON Schema (for testing)
to_json_schema(params) :: map()
```

**Supported Types:**

- `string` → `:string`
- `number` → `:number`
- `integer` → `:integer`
- `boolean` → `:boolean`
- `array` → `:array`
- `object` → `:object`
- `null` → handled as optional

**Constraints:**

- `required` → `required: true`
- `enum` → `enum: [values]`
- `minLength`, `maxLength` → preserved in description
- `minimum`, `maximum` → preserved in description

#### 4. LangChain.MCP.ToolExecutor

**Purpose:** Execute MCP tools and handle fallbacks

**Responsibilities:**

- Invoke tools via Anubis client
- Handle fallback on transient errors
- Convert results to LangChain format
- Manage execution context

**Key Functions:**

```elixir
# Execute tool with fallback support
execute_tool(config, tool_name, arguments, context \\ %{}) ::
  {:ok, result} | {:error, term()}
```

**Execution Flow:**

```
1. Validate arguments
2. Call primary client
3. Check for errors
   ├─ Success → Convert result
   ├─ Domain error → Return error (no fallback)
   └─ Transient error → Try fallback if configured
4. Convert content to LangChain format
```

#### 5. LangChain.MCP.ContentMapper

**Purpose:** Map MCP content to LangChain ContentParts

**Responsibilities:**

- Convert text content
- Convert image content (base64)
- Handle resource references
- Support multi-modal responses

**Key Functions:**

```elixir
# Map MCP content array to ContentParts
map_content(content_list) :: [%ContentPart{}]

# Map single content item
map_content_item(item) :: %ContentPart{}
```

**Content Type Mapping:**

```elixir
# Text
%{"type" => "text", "text" => "..."}
→ ContentPart.text!("...")

# Image
%{"type" => "image", "data" => "base64...", "mimeType" => "image/png"}
→ ContentPart.image!("base64...", media: "image/png")

# Resource
%{"type" => "resource", "uri" => "file:///..."}
→ ContentPart.text!("Resource: file:///...")
```

#### 6. LangChain.MCP.ErrorHandler

**Purpose:** Classify and handle MCP errors

**Responsibilities:**

- Determine error type (protocol/transport/domain)
- Decide retry-ability
- Provide user-friendly messages

**Key Functions:**

```elixir
# Classify error and determine if retryable
classify_error(error) :: {error_type, retryable?, message}

# Check if error should trigger fallback
should_retry?(error) :: boolean()
```

**Error Classification:**

```elixir
# Protocol errors (retryable)
%Error{code: -32700} # Parse error
%Error{code: -32600} # Invalid request
%Error{code: -32601} # Method not found
%Error{code: -32602} # Invalid params
%Error{code: -32603} # Internal error

# Transport errors (retryable)
%Error{reason: :send_failure}
%Error{reason: :request_timeout}
%Error{reason: :connection_refused}

# Domain errors (NOT retryable)
%Response{is_error: true, result: %{"isError" => true}}
```

### Anubis Client Layer

#### 1. Anubis.Client

**Purpose:** DSL macro for generating MCP client

**Generated API:**

- `start_link/1` - Start client GenServer
- `list_tools/1` - Discover available tools
- `call_tool/3` - Execute tool by name
- `list_resources/1` - List available resources
- `read_resource/2` - Read resource content
- `list_prompts/1` - List available prompts
- `get_prompt/3` - Get prompt with arguments
- `ping/1` - Health check
- `close/1` - Close connection

#### 2. Anubis.Client.Base (GenServer)

**Purpose:** OTP-compliant client implementation

**State Management:**

```elixir
%State{
  client_info: %{name, version},
  server_info: %{name, version},
  capabilities: %{},
  server_capabilities: %{},
  transport: %{layer, name},
  pending_requests: %{request_id => %Request{}},
  progress_callbacks: %{token => function},
  log_callback: function | nil,
  sampling_callback: function | nil,
  roots: %{uri => root_info}
}
```

**Request Lifecycle:**

```
1. Operation received via GenServer.call
2. Generate unique request ID
3. Create Request struct with timeout timer
4. Store in pending_requests map
5. Encode to JSON-RPC
6. Send via transport
7. Wait for response (async)
8. Decode response
9. Match to pending request
10. Reply to caller
11. Remove from pending_requests
```

#### 3. Anubis.MCP.Message

**Purpose:** JSON-RPC 2.0 protocol handling

**Message Format:**

```elixir
# Request
%{
  "jsonrpc" => "2.0",
  "id" => "unique-id",
  "method" => "tools/call",
  "params" => %{...}
}

# Response (success)
%{
  "jsonrpc" => "2.0",
  "id" => "unique-id",
  "result" => %{...}
}

# Response (error)
%{
  "jsonrpc" => "2.0",
  "id" => "unique-id",
  "error" => %{
    "code" => -32601,
    "message" => "Method not found"
  }
}
```

## Data Flow

### Tool Discovery Flow

```
User calls Adapter.to_functions(adapter)
    │
    ▼
Adapter checks cache
    │
    ├─ Cache hit → Return cached tools
    │
    └─ Cache miss
        │
        ▼
    Anubis.Client.list_tools(client)
        │
        ▼
    GenServer.call(client, {:operation, %{method: "tools/list"}})
        │
        ▼
    Create Request, set timeout timer
        │
        ▼
    Encode to JSON-RPC
        │
        ▼
    Transport.send_message(data)
        │
        ▼
    [Network/IPC to MCP Server]
        │
        ▼
    Server returns tool list
        │
        ▼
    Decode JSON-RPC response
        │
        ▼
    Match to pending request
        │
        ▼
    Reply {:ok, %Response{result: %{"tools" => [...]}}}
        │
        ▼
    Adapter applies filters
        │
        ▼
    SchemaConverter.convert_input_schema for each tool
        │
        ▼
    Build LangChain Function structs
        │
        ▼
    Cache tools (if enabled)
        │
        ▼
    Return [%Function{}, ...]
```

### Tool Execution Flow

```
LLM requests tool execution
    │
    ▼
LangChain calls Function.function field (callback)
    │
    ▼
ToolExecutor.execute_tool(config, name, args, context)
    │
    ▼
Primary Client: Anubis.Client.call_tool(client, name, args)
    │
    ▼
GenServer.call(client, {:operation, %{method: "tools/call"}})
    │
    ▼
Create Request, encode, send via transport
    │
    ▼
[MCP Server executes tool]
    │
    ▼
Response returns: %Response{result: %{"content" => [...], "isError" => false}}
    │
    ├─ is_error: false
    │   │
    │   ▼
    │   ContentMapper.map_content(result["content"])
    │   │
    │   ▼
    │   Return {:ok, [%ContentPart{}, ...]}
    │
    └─ is_error: true
        │
        ▼
        ErrorHandler.classify_error
        │
        ├─ Domain error (not retryable)
        │   │
        │   ▼
        │   Return {:error, result}
        │
        └─ Protocol/Transport error (retryable)
            │
            ├─ No fallback configured
            │   │
            │   ▼
            │   Return {:error, error}
            │
            └─ Fallback configured
                │
                ▼
                Call before_fallback callback
                │
                ▼
                Retry with fallback client
                │
                └─ (Same flow as primary)
```

## Module Design

### Design Patterns Used

#### 1. Macro DSL (Anubis.Client)

Generates boilerplate GenServer code:

```elixir
use Anubis.Client, name: "MyApp", version: "1.0.0"
```

Generates:

- `child_spec/1` for supervision
- All client API functions
- Protocol handling code

#### 2. Ecto Schema (LangChain.MCP.Config)

Uses Ecto for validation:

```elixir
embedded_schema do
  field :client, :any, virtual: true
  field :cache, :boolean, default: true
end

def changeset(config, attrs) do
  config
  |> cast(attrs, [:cache, ...])
  |> validate_required([:client])
  |> validate_number(:timeout, greater_than: 0)
end
```

#### 3. Fluent Builder (Response Building)

Chainable response construction:

```elixir
Response.tool()
|> Response.text("Result")
|> Response.image(data, "image/png")
|> Response.build()
```

#### 4. Strategy Pattern (Transport)

Pluggable transport implementations:

```elixir
{:stdio, command: "cmd", args: [...]}
{:streamable_http, base_url: "http://..."}
{:websocket, url: "ws://..."}
```

#### 5. Adapter Pattern (LangChain.MCP.Adapter)

Bridges incompatible interfaces:

- MCP tools → LangChain Functions
- JSON Schema → FunctionParam
- MCP content → ContentParts

## Error Handling Strategy

### Error Hierarchy

```
Errors
├── Protocol Errors (JSON-RPC)
│   ├── Parse Error (-32700)
│   ├── Invalid Request (-32600)
│   ├── Method Not Found (-32601)
│   ├── Invalid Params (-32602)
│   └── Internal Error (-32603)
│
├── Transport Errors
│   ├── Connection Refused
│   ├── Send Failure
│   ├── Request Timeout
│   └── Connection Lost
│
└── Domain Errors
    ├── Tool Execution Failed
    ├── Resource Not Found
    └── Permission Denied
```

### Retry Logic

```elixir
def should_retry?(error) do
  case classify_error(error) do
    {:protocol, true, _} -> true  # Protocol errors are transient
    {:transport, true, _} -> true  # Transport errors are transient
    {:domain, false, _} -> false   # Domain errors are permanent
  end
end
```

### Error Context

Errors include full context for debugging:

```elixir
{:error, %{
  type: :protocol_error,
  code: -32601,
  message: "Method not found: invalid_tool",
  client: MyMCP,
  tool_name: "invalid_tool",
  retryable: true
}}
```

## State Management

### Client State (Anubis)

**Lifecycle:**

```
1. init/1 - Initialize state, start transport
2. Connection established - Store server info/capabilities
3. Requests added to pending_requests map
4. Responses matched and removed from map
5. Cleanup on timeout or response
6. terminate/2 - Clean shutdown
```

**Memory Management:**

- Pending requests auto-removed on completion
- Timeout timers prevent leaks
- Callbacks stored by reference (not copied)

### Adapter State (LangChain MCP)

**Caching Strategy:**

```elixir
# First call - discover tools
adapter = Adapter.new(client: MyMCP, cache: true)
tools = Adapter.to_functions(adapter)  # Calls list_tools

# Second call - use cache
tools = Adapter.to_functions(adapter)  # No network call

# Force refresh
{:ok, fresh_tools} = Adapter.refresh_tools(adapter)
```

**Cache Invalidation:**

- Manual via `refresh_tools/1`
- No TTL (tools rarely change)
- Per-adapter (not global)

## Performance Considerations

### 1. Request Timeout

**Default:** 30 seconds per request

**Configuration:**

```elixir
Config.new!(client: MyMCP, timeout: 60_000)
```

**Implications:**

- Long timeouts block caller
- Short timeouts risk false failures
- Consider tool execution time

### 2. Tool Caching

**Impact:**

- First call: Full network round-trip (~100-500ms)
- Cached calls: Instant (<1ms)
- Memory: ~1-10 KB per tool

**Recommendation:** Enable caching unless tools change frequently

### 3. Connection Pooling

Handled by Anubis transport layer:

- STDIO: Single subprocess per client
- HTTP: Connection reuse via HTTP/1.1 keep-alive or HTTP/2
- WebSocket: Single persistent connection

### 4. Concurrent Requests

```elixir
# Anubis handles concurrent requests via GenServer queue
# Multiple tools can execute in parallel:

tasks = [
  Task.async(fn -> MyMCP.call_tool("tool1", %{}) end),
  Task.async(fn -> MyMCP.call_tool("tool2", %{}) end),
  Task.async(fn -> MyMCP.call_tool("tool3", %{}) end)
]

results = Task.await_many(tasks)
```

**Performance:**

- Requests queue in GenServer mailbox
- Single client can handle 1000+ req/sec
- Consider multiple clients for isolation

## Design Decisions

### 1. Separate Library

**Decision:** Create `langchain_mcp` as separate package

**Rationale:**

- Optional dependency (not all users need MCP)
- Independent versioning (MCP spec evolving)
- Clear separation of concerns
- Easier to test in isolation

**Trade-offs:**

- (+) Smaller core LangChain package
- (+) Users opt-in to MCP
- (-) Additional dependency to manage
- (-) Slightly more complex setup

### 2. Caching Default: Enabled

**Decision:** Cache tools by default

**Rationale:**

- Tool discovery is expensive (network call)
- Tools rarely change during runtime
- Easy to disable if needed

**Trade-offs:**

- (+) Much faster repeated access
- (+) Reduces server load
- (-) Stale tools if server changes
- (-) Slightly more memory

### 3. Fallback Pattern

**Decision:** Similar to LLMChain's `with_fallbacks`

**Rationale:**

- Consistent with existing LangChain patterns
- Users already familiar with concept
- Production resilience requirement

**Trade-offs:**

- (+) High availability
- (+) Familiar API
- (-) More complex configuration
- (-) Can hide underlying issues

### 4. Error Classification

**Decision:** Three distinct error types with different retry logic

**Rationale:**

- MCP spec defines these categories
- Not all errors should trigger fallback
- Fine-grained control for applications

**Trade-offs:**

- (+) Precise retry behavior
- (+) Better error messages
- (-) More complex error handling
- (-) Requires understanding distinctions

### 5. Synchronous by Default

**Decision:** Tool execution blocks by default

**Rationale:**

- Matches LangChain function calling behavior
- Simpler mental model
- Async available as option

**Trade-offs:**

- (+) Simple, predictable behavior
- (+) Easier debugging
- (-) Can't cancel in-flight requests
- (-) Blocks caller during execution

### 6. No Built-in Rate Limiting

**Decision:** Don't include rate limiting in adapter

**Rationale:**

- Rate limits vary by server
- Application-level concern
- Can be added via middleware

**Trade-offs:**

- (+) Simpler implementation
- (+) More flexible
- (-) Users must implement if needed
- (-) Risk of overwhelming server

### 7. Minimal Schema Validation

**Decision:** Trust MCP server's schema validation

**Rationale:**

- Server performs validation anyway
- Avoids duplicate code
- Faster execution

**Trade-offs:**

- (+) Simpler adapter code
- (+) No schema drift
- (-) Later error detection
- (-) Less helpful error messages

## Future Enhancements

### Considered but Deferred

1. **Telemetry Integration**
    - Emit events for tool discovery/execution
    - Match LangChain's telemetry patterns
    - Useful for monitoring

2. **Progress Callbacks**
    - Map MCP progress notifications
    - Update LangChain callbacks
    - Support long-running tools

3. **Resource Support**
    - MCP has resources in addition to tools
    - Could be exposed as functions
    - Different use case than tools

4. **Prompt Templates**
    - MCP supports prompt templates
    - Could integrate with LangChain prompts
    - Separate feature

5. **Connection Pooling**
    - Multiple clients to same server
    - Load balancing
    - Currently handled by Anubis

6. **Dynamic Tool Discovery**
    - Refresh tools during chain execution
    - React to server changes
    - More complex lifecycle

## Testing Architecture

### Test Server

**LangChain.MCP.TestServer:**

- Native Elixir MCP server
- HTTP transport (streamable_http)
- Three test tools
- Started via `mix test_server`

**Architecture:**

```
Bandit HTTP Server (port 5000)
    │
    ▼
Plug Router
    │
    ▼
Anubis.Transport.StreamableHTTP.Plug
    │
    ▼
LangChain.MCP.TestServer (MCP Server)
```

### Test Strategy

1. **Unit Tests** - Mock Anubis client, test adapter logic
2. **Integration Tests** - Real test server, `@tag :live_call`
3. **Property Tests** - Schema conversion edge cases

See [TESTING.md](TESTING.md) for details.

## References

- **MCP Specification:** https://modelcontextprotocol.io/
- **Anubis Documentation:** https://hexdocs.pm/anubis_mcp/
- **LangChain Elixir:** https://hexdocs.pm/langchain/
- **JSON-RPC 2.0:** https://www.jsonrpc.org/specification

---

**Last Updated:** 2025-11-10
