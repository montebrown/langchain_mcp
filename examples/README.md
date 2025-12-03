# StatusMonitor Examples

This directory contains examples of how to use the LangChain MCP StatusMonitor feature.

## Examples

### 1. Basic Usage (`basic_usage.exs`)

A comprehensive script demonstrating all StatusMonitor features:

```bash
elixir examples/basic_usage.exs
```

This example shows:

- Registering clients
- Checking registration status
- Listing all clients
- Getting individual client status
- Performing health checks
- Getting health summaries
- Monitoring periodic status updates
- Getting full dashboard status
- Handling client failures
- Unregistering clients

### 2. Phoenix LiveView (`phoenix_liveview_example.ex`)

A complete Phoenix LiveView implementation for real-time status monitoring.

Features:

- Auto-refreshing dashboard (every 2 seconds)
- Color-coded status indicators
- Health summary with uptime percentage
- Detailed client information
- Responsive design with Tailwind CSS

#### Installation

1. Copy `phoenix_liveview_example.ex` to your Phoenix app at `lib/my_app_web/live/mcp_status_live.ex`

2. Add route to your router:

```elixir
# lib/my_app_web/router.ex
scope "/", MyAppWeb do
  pipe_through :browser

  live "/mcp/status", MCPStatusLive
end
```

3. Register your MCP clients with StatusMonitor:

```elixir
# In your client module
defmodule MyApp.GitHubMCP do
  use LangChain.MCP.Client,
    name: "GitHub MCP",
    version: "1.0.0"
```

Or register in your Application module:

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {MyApp.GitHubMCP, transport: {:streamable_http, base_url: "http://localhost:5000"}}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    # Register clients after they start
    register_clients()

    {:ok, pid}
  end

  defp register_clients do
    Process.sleep(100)  # Wait for clients to start

    # Register each client
    [{MyApp.GitHubMCP, :github}, {MyApp.FileSystemMCP, :filesystem}]
    |> Enum.each(fn {module, name} ->
      case Process.whereis(module) do
        nil -> :ok
        pid -> LangChain.MCP.StatusMonitor.register_client(name, pid)
      end
    end)
  end
end
```

4. Visit `http://localhost:4000/mcp/status` in your browser

## API Overview

### Core Functions

```elixir
# Register a client
StatusMonitor.register_client(:github, pid)

# Unregister a client
StatusMonitor.unregister_client(:github)

# Check if registered
StatusMonitor.registered?(:github)

# List all clients
StatusMonitor.list_clients()

# Count clients
StatusMonitor.count_clients()
```

### Status Queries

```elixir
# Get single client status
{:ok, %{pid: pid}} = StatusMonitor.get_client_status(:github)

# Get all clients status
all_status = StatusMonitor.get_all_clients_status()

# Health check
{ping_result, status_result} = StatusMonitor.health_check(:github)

# Health summary
%{
  healthy_clients: [...],
  unhealthy_clients: [...],
  total_clients: 2,
  uptime_percentage: 50.0
} = StatusMonitor.health_summary()
```

### Dashboard Functions

```elixir
# Periodic status (simplified for polling)
StatusMonitor.periodic_status_update()
# => %{
#   github: %{ready?: true},
#   filesystem: %{ready?: false, error: :client_not_registered}
# }

# Full dashboard status
StatusMonitor.dashboard_status()
# => %{
#   clients: %{
#     github: %{status: :healthy, pid: #PID<0.123.0>, alive?: true},
#     filesystem: %{status: :unhealthy, error: :process_dead, alive?: false}
#   },
#   summary: %{...},
#   timestamp: 1234567890
# }
```

## Best Practices

1. **Auto-register clients**: Have clients register themselves in their `init/1` callback
2. **Monitor periodically**: Use `periodic_status_update/0` for polling or LiveView for real-time updates
3. **Handle failures gracefully**: Check `registered?/1` before operations
4. **Clean up**: Unregister clients when shutting down (optional, Registry handles this automatically)

## Troubleshooting

### Clients not appearing in dashboard

- Ensure clients are started before registering
- Check that `Application.ensure_all_started(:langchain_mcp)` is called
- Verify clients are GenServers (have a PID)

### Status shows "unhealthy"

- Client process may have crashed
- Check logs for errors in client initialization
- Verify transport configuration is correct

### Registry errors

- Ensure the LangChain.MCP application is started
- Check that the Registry is running: `Process.whereis(:langchain_mcp_clients)`
