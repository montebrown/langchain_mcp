# StatusMonitor Feature

A lightweight, Registry-based solution for monitoring the real-time status of MCP clients in your LangChain Elixir application.

## Overview

The StatusMonitor module provides a simple way to track and display the health of multiple MCP clients without requiring additional GenServers. Each client registers itself with the StatusMonitor, which leverages Elixir's built-in Registry for efficient client tracking.

## Features

- **Zero-overhead monitoring**: Uses Elixir Registry, no additional GenServers needed
- **Real-time status tracking**: Query client health at any time
- **Health summaries**: Get uptime percentages and overall system health
- **Dashboard-ready**: Pre-built functions optimized for LiveView dashboards
- **Full test coverage**: 29 comprehensive tests ensuring reliability

## Architecture

```
┌─────────────────────────┐
│   MCP Client            │
│   (GenServer)           │
└────────┬────────────────┘
         │ registers itself
         ▼
┌─────────────────────────┐
│   StatusMonitor         │
│   (Module)              │
└────────┬────────────────┘
         │ queries
         ▼
┌─────────────────────────┐
│   Registry              │
│   (:langchain_mcp_      │
│    clients)             │
└─────────────────────────┘
```

## Quick Start

### 1. Define Your MCP Client

Use `LangChain.MCP.Client` to decouple from `Anubis.Client`:

```elixir
defmodule MyApp.GitHubMCP do
  use LangChain.MCP.Client,
    name: "GitHub MCP",
    version: "1.0.0",
    protocol_version: "2025-03-26"
end
```

### 2. Register with StatusMonitor

Register clients from your Application module:

```elixir
defmodule MyApp.Application do
  use Application
  alias LangChain.MCP.StatusMonitor

  def start(_type, _args) do
    children = [
      {MyApp.GitHubMCP,
        transport: {:streamable_http, base_url: "http://localhost:5000"}}
    ]

    {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one)

    # Register clients for status monitoring
    StatusMonitor.register_client_by_name(MyApp.GitHubMCP, :github)

    {:ok, self()}
  end
end
```

### 3. Query Status

```elixir
alias LangChain.MCP.StatusMonitor

# Check if registered
StatusMonitor.registered?(:github)
#=> true

# Get client status
StatusMonitor.get_client_status(:github)
#=> {:ok, %{pid: #PID<0.123.0>}}

# Get health summary
StatusMonitor.health_summary()
#=> %{
#     healthy_clients: [:github, :filesystem],
#     unhealthy_clients: [],
#     total_clients: 2,
#     uptime_percentage: 100.0
#   }
```

### 3. Use in Phoenix LiveView

See `examples/phoenix_liveview_example.ex` for a complete, production-ready LiveView implementation with:
- Auto-refreshing dashboard (every 2 seconds)
- Color-coded status indicators
- Detailed client information
- Responsive Tailwind CSS design

## API Reference

### Registration Functions

- `register_client(name, pid)` - Register a client for monitoring
- `register_client_by_name(module, name, timeout \\ 5_000)` - Wait for and register a client by module name
- `unregister_client(name)` - Unregister a client (optional, Registry handles cleanup)
- `registered?(name)` - Check if a client is registered

### Query Functions

- `get_client_status(name)` - Get status of a specific client
- `get_all_clients_status()` - Get status of all registered clients
- `list_clients()` - List all registered client names
- `count_clients()` - Get count of registered clients

### Health Functions

- `health_check(name)` - Perform comprehensive health check
- `health_summary()` - Get overall health summary with uptime percentage
- `periodic_status_update()` - Simplified status for polling/LiveView
- `dashboard_status()` - Complete status package for dashboards

## Examples

### Basic Usage Script

Run the included example to see all features in action:

```bash
elixir examples/basic_usage.exs
```

This demonstrates:
- Client registration
- Status queries
- Health checks
- Failure handling
- Cleanup

### Phoenix LiveView Integration

1. Copy `examples/phoenix_liveview_example.ex` to your Phoenix app
2. Add route: `live "/mcp/status", MCPStatusLive`
3. Visit `http://localhost:4000/mcp/status`

See `examples/README.md` for detailed setup instructions.

## Testing

The StatusMonitor has comprehensive test coverage (29 tests):

```bash
mix test test/langchain/mcp/status_monitor_test.exs
```

Tests cover:
- Client registration/unregistration
- Status queries
- Health checks
- Health summaries
- Periodic updates
- Dashboard status
- Client failures
- Edge cases

## Implementation Details

### Why Registry?

- **Lightweight**: No additional GenServer overhead
- **Built-in**: Part of Elixir standard library
- **Efficient**: O(1) lookups
- **Automatic cleanup**: When a client crashes, Registry removes it automatically
- **Scalable**: Handles thousands of clients easily

### Application Startup

The StatusMonitor requires the Registry to be started. This happens automatically via:

```elixir
# lib/langchain_mcp/application.ex
defmodule LangChain.MCP.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: :langchain_mcp_clients}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### Test Isolation

Tests use `async: true` and clean up registrations in an `on_exit` callback to ensure isolation:

```elixir
setup do
  on_exit(fn ->
    StatusMonitor.unregister_client(:test_client)
  end)
  :ok
end
```

## Best Practices

1. **Use LangChain.MCP.Client**: Prefer `use LangChain.MCP.Client` instead of `Anubis.Client` to keep your app decoupled from the underlying MCP implementation
2. **Register in Application**: Register clients from your Application module using `register_client_by_name/3`
3. **Naming convention**: Use atoms for client names (e.g., `:github`, `:filesystem`)
4. **Error handling**: Always pattern match on status results
5. **Monitoring frequency**: Poll `periodic_status_update/0` every 2-5 seconds for dashboards
6. **Cleanup**: Let Registry handle cleanup automatically; manual unregistration is optional

## Performance

- **Registration**: O(1) - Uses Registry.register/3
- **Lookup**: O(1) - Uses Registry.lookup/2
- **List all**: O(n) - Uses Registry.select/2
- **Health summary**: O(n) - Iterates through all clients once

The StatusMonitor is designed for real-time applications and can easily handle hundreds of clients with minimal overhead.

## Troubleshooting

### Registry not found

**Error**: `ArgumentError: unknown registry: :langchain_mcp_clients`

**Solution**: Ensure the LangChain.MCP application is started:
```elixir
Application.ensure_all_started(:langchain_mcp)
```

### Clients not appearing

**Issue**: `list_clients/0` returns empty list

**Checklist**:
1. Are clients started? Check `Process.whereis(MyApp.ClientModule)`
2. Did clients call `register_client/2`?
3. Are clients GenServers with a PID?

### Status shows unhealthy

**Issue**: Client shows as `:unhealthy` in dashboard

**Common causes**:
1. Client process crashed - check logs
2. Client not fully initialized
3. Transport connection failed

## Future Enhancements

Potential additions (not yet implemented):

- PubSub notifications for status changes
- Metrics integration (Telemetry)
- Historical uptime tracking
- Custom health check callbacks
- Clustering support for distributed systems

## Contributing

When adding new features:

1. Write tests first (TDD)
2. Update this documentation
3. Add examples if appropriate
4. Ensure all tests pass: `mix test`

## License

Apache 2.0 - See LICENSE file for details
