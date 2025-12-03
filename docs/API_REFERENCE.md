# LangChain MCP API Reference

Complete API documentation for the LangChain MCP integration library and related Anubis client APIs.

## Table of Contents

1. [LangChain.MCP.Adapter](#langchainmcpadapter)
2. [LangChain.MCP.Config](#langchainmcpconfig)
3. [LangChain.MCP.SchemaConverter](#langchainmcpschemaconverter)
4. [LangChain.MCP.ContentMapper](#langchainmcpcontentmapper)
5. [LangChain.MCP.ErrorHandler](#langchainmcperrorhandler)
6. [LangChain.MCP.ToolExecutor](#langchainmcptoolexecutor)
7. [Anubis.Client API](#anubisclient-api)
8. [Data Structures](#data-structures)

---

## LangChain.MCP.Adapter

Main entry point for MCP integration.

### new/1

Creates a new adapter instance with configuration.

**Signature:**

```elixir
@spec new(keyword() | map()) :: {:ok, %Adapter{}} | {:error, Ecto.Changeset.t()}
```

**Options:**

- `:client` (required) - Anubis client module (e.g., `MyApp.GitHubMCP`)
- `:fallback_client` - Optional fallback client module
- `:cache` - Enable tool caching (default: `true`)
- `:timeout` - Request timeout in ms (default: `30_000`)
- `:async` - Async execution (default: `true`)
- `:filter` - Filter mode (`:only`, `:except`, `:none`)
- `:filter_list` - List of tool names to include/exclude
- `:filter_fn` - Custom filter function `(tool :: map()) -> boolean()`
- `:before_fallback` - Callback before fallback `(error, context) -> any()`

**Examples:**

```elixir
# Basic usage
{:ok, adapter} = Adapter.new(client: MyApp.MCP)

# With fallback
{:ok, adapter} = Adapter.new(
  client: MyApp.PrimaryMCP,
  fallback_client: MyApp.BackupMCP,
  before_fallback: fn error, context ->
    Logger.warning("Fallback triggered: #{inspect(error)}")
  end
)

# With filtering
{:ok, adapter} = Adapter.new(
  client: MyApp.MCP,
  filter: :only,
  filter_list: ["search", "create_issue"]
)

# With custom filter
{:ok, adapter} = Adapter.new(
  client: MyApp.MCP,
  filter_fn: fn tool ->
    String.starts_with?(tool["name"], "safe_")
  end
)
```

**Returns:**

- `{:ok, %Adapter{}}` - Successfully created adapter
- `{:error, changeset}` - Validation failed

**Errors:**

- Missing required `:client`
- Invalid timeout (must be > 0)
- Invalid filter mode
- Filter list not provided when filter is `:only` or `:except`

---

### new!/1

Same as `new/1` but raises on error.

**Signature:**

```elixir
@spec new!(keyword() | map()) :: %Adapter{}
```

**Example:**

```elixir
adapter = Adapter.new!(client: MyApp.MCP)
```

**Raises:** `ArgumentError` if validation fails

---

### to_functions/2

Discovers MCP tools and converts them to LangChain Functions.

**Signature:**

```elixir
@spec to_functions(%Adapter{}, keyword()) :: [%Function{}]
```

**Options:**

- `:force_refresh` - Bypass cache and fetch fresh tools (default: `false`)

**Example:**

```elixir
# Use cached tools (if available)
functions = Adapter.to_functions(adapter)

# Force refresh
functions = Adapter.to_functions(adapter, force_refresh: true)
```

**Returns:** List of `LangChain.Function` structs

**Side Effects:**

- May call `Anubis.Client.list_tools/1` if cache miss
- Caches result if `:cache` is enabled

**Errors:**
Returns empty list `[]` if tool discovery fails (logs error)

---

### refresh_tools/1

Explicitly refresh tool cache.

**Signature:**

```elixir
@spec refresh_tools(%Adapter{}) :: {:ok, [map()]} | {:error, term()}
```

**Example:**

```elixir
{:ok, fresh_tools} = Adapter.refresh_tools(adapter)
```

**Returns:**

- `{:ok, tools}` - List of raw MCP tool definitions
- `{:error, reason}` - Tool discovery failed

---

## LangChain.MCP.Config

Configuration validation and storage.

### new/1

Creates validated configuration.

**Signature:**

```elixir
@spec new(keyword() | map()) :: {:ok, %Config{}} | {:error, Ecto.Changeset.t()}
```

**Schema Fields:**

```elixir
%Config{
  client: module(),              # Required
  fallback_client: module() | nil,
  cache: boolean(),              # Default: true
  timeout: pos_integer(),        # Default: 30_000
  async: boolean(),              # Default: true
  filter: :only | :except | :none,  # Default: :none
  filter_list: [String.t()],     # Default: []
  filter_fn: function() | nil,
  before_fallback: function() | nil
}
```

**Validations:**

- `:client` is required
- `:timeout` must be > 0
- If `:filter` is `:only` or `:except`, `:filter_list` must be provided
- Cannot specify both `:filter_list` and `:filter_fn`

**Example:**

```elixir
{:ok, config} = Config.new(
  client: MyApp.MCP,
  cache: true,
  timeout: 60_000
)
```

---

### new!/1

Same as `new/1` but raises on error.

**Signature:**

```elixir
@spec new!(keyword() | map()) :: %Config{}
```

---

### changeset/2

Creates Ecto changeset for validation.

**Signature:**

```elixir
@spec changeset(%Config{}, map()) :: Ecto.Changeset.t()
```

**Example:**

```elixir
changeset = Config.changeset(%Config{}, %{client: MyApp.MCP})
if changeset.valid? do
  config = Ecto.Changeset.apply_changes(changeset)
end
```

---

## LangChain.MCP.SchemaConverter

Converts between JSON Schema and LangChain FunctionParam.

### convert_input_schema/1

Convert JSON Schema to LangChain parameters.

**Signature:**

```elixir
@spec convert_input_schema(map()) :: [%FunctionParam{}]
```

**Input Format:**

```elixir
%{
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
```

**Output Format:**

```elixir
[
  %FunctionParam{
    name: "query",
    type: :string,
    description: "Search query",
    required: true
  },
  %FunctionParam{
    name: "limit",
    type: :integer,
    description: "Must be >= 1 and <= 100",
    required: false
  }
]
```

**Supported Type Mappings:**

- `"string"` → `:string`
- `"number"` → `:number`
- `"integer"` → `:integer`
- `"boolean"` → `:boolean`
- `"array"` → `:array`
- `"object"` → `:object`

**Supported Constraints:**

- `required` - Marks parameter as required
- `enum` - Converted to `enum: [values]`
- `minimum`, `maximum` - Added to description
- `minLength`, `maxLength` - Added to description
- `pattern` - Added to description
- `default` - Preserved in parameter

**Examples:**

```elixir
# Simple types
schema = %{
  "type" => "object",
  "properties" => %{"name" => %{"type" => "string"}},
  "required" => ["name"]
}
params = SchemaConverter.convert_input_schema(schema)
# [%FunctionParam{name: "name", type: :string, required: true}]

# Enum type
schema = %{
  "type" => "object",
  "properties" => %{
    "status" => %{"type" => "string", "enum" => ["open", "closed"]}
  }
}
params = SchemaConverter.convert_input_schema(schema)
# [%FunctionParam{name: "status", type: :string, enum: ["open", "closed"]}]

# Nested object
schema = %{
  "type" => "object",
  "properties" => %{
    "config" => %{
      "type" => "object",
      "properties" => %{
        "debug" => %{"type" => "boolean"}
      }
    }
  }
}
params = SchemaConverter.convert_input_schema(schema)
# [%FunctionParam{name: "config", type: :object, ...}]
```

**Returns:** List of `FunctionParam` structs

**Notes:**

- Empty schema returns `[]`
- Invalid schema logs warning and returns `[]`
- Constraints added to parameter description

---

### to_json_schema/1

Convert LangChain parameters back to JSON Schema.

**Signature:**

```elixir
@spec to_json_schema([%FunctionParam{}]) :: map()
```

**Example:**

```elixir
params = [
  %FunctionParam{name: "query", type: :string, required: true}
]
schema = SchemaConverter.to_json_schema(params)
# %{
#   "type" => "object",
#   "properties" => %{"query" => %{"type" => "string"}},
#   "required" => ["query"]
# }
```

**Use Case:** Testing, validation, debugging

---

## LangChain.MCP.ContentMapper

Maps MCP content to LangChain ContentParts.

### map_content/1

Convert MCP content array to ContentParts.

**Signature:**

```elixir
@spec map_content([map()]) :: [%ContentPart{}]
```

**Input Format:**

```elixir
[
  %{"type" => "text", "text" => "Hello"},
  %{"type" => "image", "data" => "base64...", "mimeType" => "image/png"},
  %{"type" => "resource", "uri" => "file:///path"}
]
```

**Output Format:**

```elixir
[
  %ContentPart{type: :text, content: "Hello"},
  %ContentPart{type: :image, content: "base64...", options: %{media: "image/png"}},
  %ContentPart{type: :text, content: "Resource: file:///path"}
]
```

**Examples:**

```elixir
# Text content
content = [%{"type" => "text", "text" => "Result"}]
parts = ContentMapper.map_content(content)
# [%ContentPart{type: :text, content: "Result"}]

# Image content
content = [%{
  "type" => "image",
  "data" => "iVBORw0KGgo...",
  "mimeType" => "image/png"
}]
parts = ContentMapper.map_content(content)
# [%ContentPart{type: :image, content: "iVBORw0KGgo...", options: %{media: "image/png"}}]

# Mixed content
content = [
  %{"type" => "text", "text" => "Here's an image:"},
  %{"type" => "image", "data" => "...", "mimeType" => "image/jpeg"}
]
parts = ContentMapper.map_content(content)
# [text ContentPart, image ContentPart]
```

**Returns:** List of `ContentPart` structs

**Notes:**

- Unknown types logged as warning and converted to text
- Empty list returns `[]`
- Resources converted to text descriptions

---

### map_content_item/1

Map single MCP content item.

**Signature:**

```elixir
@spec map_content_item(map()) :: %ContentPart{}
```

**Example:**

```elixir
item = %{"type" => "text", "text" => "Hello"}
part = ContentMapper.map_content_item(item)
# %ContentPart{type: :text, content: "Hello"}
```

---

## LangChain.MCP.ErrorHandler

Error classification and handling.

### classify_error/1

Classify error and determine retry-ability.

**Signature:**

```elixir
@spec classify_error(term()) :: {error_type, retryable?, message}
when error_type: :protocol | :transport | :domain
```

**Examples:**

```elixir
# Protocol error
error = %Anubis.MCP.Error{code: -32601, reason: :method_not_found}
{type, retryable, msg} = ErrorHandler.classify_error(error)
# {:protocol, true, "Protocol error: method_not_found"}

# Transport error
error = %Anubis.MCP.Error{reason: :send_failure}
{type, retryable, msg} = ErrorHandler.classify_error(error)
# {:transport, true, "Transport error: send_failure"}

# Domain error
error = %Anubis.MCP.Response{is_error: true, result: %{"isError" => true}}
{type, retryable, msg} = ErrorHandler.classify_error(error)
# {:domain, false, "Tool execution failed"}
```

**Return Values:**

- `{:protocol, true, message}` - JSON-RPC protocol error (retryable)
- `{:transport, true, message}` - Connection error (retryable)
- `{:domain, false, message}` - Tool execution error (not retryable)
- `{:unknown, false, message}` - Unknown error (not retryable)

---

### should_retry?/1

Determine if error should trigger fallback.

**Signature:**

```elixir
@spec should_retry?(term()) :: boolean()
```

**Example:**

```elixir
if ErrorHandler.should_retry?(error) do
  # Try fallback client
else
  # Return error to user
end
```

**Returns:**

- `true` - Protocol or transport error
- `false` - Domain or unknown error

---

## LangChain.MCP.ToolExecutor

Tool execution with fallback support.

### execute_tool/4

Execute MCP tool through Anubis client.

**Signature:**

```elixir
@spec execute_tool(%Config{}, String.t(), map(), map()) ::
  {:ok, result} | {:error, term()}
```

**Parameters:**

- `config` - Adapter configuration
- `tool_name` - Name of tool to execute
- `arguments` - Tool arguments as map
- `context` - Execution context (default: `%{}`)

**Example:**

```elixir
config = Config.new!(client: MyApp.MCP)
{:ok, result} = ToolExecutor.execute_tool(
  config,
  "search",
  %{"query" => "elixir"},
  %{user_id: "123"}
)
```

**Flow:**

1. Call `Anubis.Client.call_tool(client, tool_name, arguments)`
2. Check response for errors
3. If transient error and fallback configured, try fallback
4. Convert successful result to ContentParts
5. Return result

**Returns:**

- `{:ok, [%ContentPart{}, ...]}` - Success
- `{:error, reason}` - Failure (after retries if configured)

**Errors:**

- `{:error, :method_not_found}` - Tool doesn't exist
- `{:error, :invalid_params}` - Invalid arguments
- `{:error, :request_timeout}` - Timeout
- `{:error, reason}` - Tool execution failed

---

## Anubis.Client API

The Anubis client provides the low-level MCP protocol interface.

### Defining a Client

```elixir
defmodule MyApp.MCPClient do
  use Anubis.Client,
    name: "MyApp",
    version: "1.0.0",
    protocol_version: "2025-03-26",
    capabilities: [:roots, {:sampling, list_changed?: true}]
end
```

**Options:**

- `:name` (required) - Client name
- `:version` (required) - Client version
- `:protocol_version` (required) - MCP protocol version
- `:capabilities` - List of capabilities to advertise

---

### start_link/1

Start the client GenServer.

**Signature:**

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
```

**Options:**

- `:transport` (required) - Transport configuration
- `:name` - GenServer name (atom or via tuple)

**Transport Options:**

```elixir
# STDIO (subprocess)
{:stdio, command: "npx", args: ["mcp-server"]}

# HTTP with SSE
{:streamable_http, base_url: "http://localhost:5000"}

# Server-Sent Events
{:sse, base_url: "http://localhost:8000"}

# WebSocket
{:websocket, url: "ws://localhost:8000/ws"}
```

**Example:**

```elixir
{:ok, pid} = MyApp.MCPClient.start_link(
  transport: {:streamable_http, base_url: "http://localhost:5000"},
  name: :my_mcp_client
)
```

---

### list_tools/1

Discover available tools from server.

**Signature:**

```elixir
@spec list_tools(GenServer.name()) :: {:ok, %Response{}} | {:error, term()}
```

**Example:**

```elixir
{:ok, response} = MyApp.MCPClient.list_tools(:my_mcp_client)
tools = response.result["tools"]
# [%{"name" => "search", "description" => "...", "inputSchema" => ...}, ...]
```

**Response Format:**

```elixir
%Response{
  result: %{
    "tools" => [
      %{
        "name" => String.t(),
        "description" => String.t(),
        "inputSchema" => map()
      }
    ],
    "nextCursor" => String.t() | nil
  }
}
```

---

### call_tool/3

Execute a tool by name.

**Signature:**

```elixir
@spec call_tool(GenServer.name(), String.t(), map()) ::
  {:ok, %Response{}} | {:error, term()}
```

**Example:**

```elixir
{:ok, response} = MyApp.MCPClient.call_tool(
  :my_mcp_client,
  "search",
  %{"query" => "elixir programming"}
)

if response.is_error do
  IO.puts("Tool failed: #{inspect(response.result)}")
else
  IO.inspect(response.result["content"])
end
```

**Response Format:**

```elixir
%Response{
  result: %{
    "content" => [
      %{"type" => "text", "text" => "..."},
      %{"type" => "image", "data" => "...", "mimeType" => "..."}
    ],
    "isError" => boolean()
  },
  is_error: boolean()
}
```

---

### list_resources/1

List available resources.

**Signature:**

```elixir
@spec list_resources(GenServer.name()) :: {:ok, %Response{}} | {:error, term()}
```

**Example:**

```elixir
{:ok, response} = MyApp.MCPClient.list_resources(:my_mcp_client)
resources = response.result["resources"]
```

---

### read_resource/2

Read a specific resource.

**Signature:**

```elixir
@spec read_resource(GenServer.name(), String.t()) ::
  {:ok, %Response{}} | {:error, term()}
```

**Example:**

```elixir
{:ok, response} = MyApp.MCPClient.read_resource(
  :my_mcp_client,
  "file:///path/to/file"
)
contents = response.result["contents"]
```

---

### list_prompts/1

List available prompt templates.

**Signature:**

```elixir
@spec list_prompts(GenServer.name()) :: {:ok, %Response{}} | {:error, term()}
```

---

### get_prompt/3

Get a prompt template with arguments.

**Signature:**

```elixir
@spec get_prompt(GenServer.name(), String.t(), map()) ::
  {:ok, %Response{}} | {:error, term()}
```

**Example:**

```elixir
{:ok, response} = MyApp.MCPClient.get_prompt(
  :my_mcp_client,
  "code_review",
  %{language: "elixir", file: "lib/my_app.ex"}
)
messages = response.result["messages"]
```

---

### ping/1

Health check.

**Signature:**

```elixir
@spec ping(GenServer.name()) :: :pong
```

**Example:**

```elixir
:pong = MyApp.MCPClient.ping(:my_mcp_client)
```

---

### close/1

Close client connection.

**Signature:**

```elixir
@spec close(GenServer.name()) :: :ok
```

**Example:**

```elixir
:ok = MyApp.MCPClient.close(:my_mcp_client)
```

---

## Data Structures

### LangChain.MCP.Adapter

```elixir
%Adapter{
  config: %Config{},
  cached_tools: [map()] | nil
}
```

### LangChain.MCP.Config

```elixir
%Config{
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
```

### Anubis.MCP.Response

```elixir
%Anubis.MCP.Response{
  result: map(),
  id: String.t(),
  is_error: boolean(),
  method: String.t() | nil
}
```

### Anubis.MCP.Error

```elixir
%Anubis.MCP.Error{
  code: integer(),
  reason: atom(),
  message: String.t(),
  data: map()
}
```

### LangChain.Function

```elixir
%LangChain.Function{
  name: String.t(),
  description: String.t(),
  parameters_schema: %FunctionParam{} | nil,
  parameters: [%FunctionParam{}],
  function: (map(), map() -> any())
}
```

### LangChain.FunctionParam

```elixir
%LangChain.FunctionParam{
  name: String.t(),
  type: :string | :number | :integer | :boolean | :array | :object,
  description: String.t(),
  required: boolean(),
  enum: [any()] | nil,
  default: any() | nil
}
```

### LangChain.ContentPart

```elixir
%LangChain.ContentPart{
  type: :text | :image | :audio,
  content: String.t(),
  options: map()
}
```

---

## Common Patterns

### Tool Discovery and Execution

```elixir
# 1. Start client
{:ok, _} = MyApp.MCP.start_link(
  transport: {:streamable_http, base_url: "http://localhost:5000"},
  name: :my_mcp
)

# 2. Create adapter
{:ok, adapter} = Adapter.new(client: MyApp.MCP)

# 3. Discover tools
functions = Adapter.to_functions(adapter)

# 4. Use in LLMChain
{:ok, chain} =
  LLMChain.new!(%{llm: llm})
  |> LLMChain.add_tools(functions)
  |> LLMChain.run()
```

### Error Handling

```elixir
case ToolExecutor.execute_tool(config, tool_name, args) do
  {:ok, content_parts} ->
    # Success
    {:ok, content_parts}

  {:error, error} ->
    case ErrorHandler.classify_error(error) do
      {:domain, false, msg} ->
        # Tool execution failed (not transient)
        {:error, msg}

      {:transport, true, msg} ->
        # Connection issue (might recover)
        Logger.warning("Transport error: #{msg}")
        {:error, msg}

      {:protocol, true, msg} ->
        # Protocol issue (likely server bug)
        Logger.error("Protocol error: #{msg}")
        {:error, msg}
    end
end
```

### Custom Filtering

```elixir
# Only allow safe operations
{:ok, adapter} = Adapter.new(
  client: MyApp.MCP,
  filter_fn: fn tool ->
    safe_prefixes = ["read_", "list_", "search_"]
    Enum.any?(safe_prefixes, &String.starts_with?(tool["name"], &1))
  end
)
```

### Fallback Configuration

```elixir
{:ok, adapter} = Adapter.new(
  client: MyApp.PrimaryMCP,
  fallback_client: MyApp.BackupMCP,
  before_fallback: fn error, context ->
    Sentry.capture_message("MCP fallback triggered",
      extra: %{error: error, context: context}
    )
  end
)
```

---

**Last Updated:** 2025-11-10
