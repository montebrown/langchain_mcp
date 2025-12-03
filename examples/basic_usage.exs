#!/usr/bin/env elixir

# Basic Usage Example for LangChain MCP StatusMonitor
#
# This example demonstrates how to:
# 1. Start MCP clients
# 2. Register them with StatusMonitor
# 3. Query their status
# 4. Monitor health

Mix.install([
  {:langchain_mcp, path: Path.expand("..", __DIR__)},
  {:anubis_mcp, "~> 0.16.0"}
])

# Ensure the application is started
Application.ensure_all_started(:langchain_mcp)

alias LangChain.MCP.StatusMonitor

IO.puts("\n=== LangChain MCP StatusMonitor Basic Usage ===\n")

# Example 1: Register a client (simulated with Agent)
IO.puts("1. Starting and registering a client...")
{:ok, client1_pid} = Agent.start_link(fn -> %{name: "GitHub MCP"} end)
{:ok, _} = StatusMonitor.register_client(:github, client1_pid)
IO.puts("   ✓ Registered :github client")

{:ok, client2_pid} = Agent.start_link(fn -> %{name: "Filesystem MCP"} end)
{:ok, _} = StatusMonitor.register_client(:filesystem, client2_pid)
IO.puts("   ✓ Registered :filesystem client")

# Example 2: Check if a client is registered
IO.puts("\n2. Checking registration status...")
IO.puts("   :github registered? #{StatusMonitor.registered?(:github)}")
IO.puts("   :unknown registered? #{StatusMonitor.registered?(:unknown)}")

# Example 3: List all clients
IO.puts("\n3. Listing all registered clients...")
clients = StatusMonitor.list_clients()
IO.puts("   Found #{length(clients)} clients: #{inspect(clients)}")

# Example 4: Get individual client status
IO.puts("\n4. Getting individual client status...")

case StatusMonitor.get_client_status(:github) do
  {:ok, status} ->
    IO.puts("   :github status: healthy")
    IO.puts("   PID: #{inspect(status.pid)}")

  {:error, reason} ->
    IO.puts("   :github status: error - #{inspect(reason)}")
end

# Example 5: Perform health check
IO.puts("\n5. Performing health check...")
{ping, status} = StatusMonitor.health_check(:github)
IO.puts("   Ping result: #{inspect(ping)}")
IO.puts("   Status result: #{inspect(status)}")

# Example 6: Get health summary
IO.puts("\n6. Getting health summary...")
summary = StatusMonitor.health_summary()
IO.puts("   Total clients: #{summary.total_clients}")
IO.puts("   Healthy: #{length(summary.healthy_clients)}")
IO.puts("   Unhealthy: #{length(summary.unhealthy_clients)}")
IO.puts("   Uptime: #{Float.round(summary.uptime_percentage, 2)}%")

# Example 7: Get periodic status update (suitable for polling)
IO.puts("\n7. Getting periodic status update...")
periodic = StatusMonitor.periodic_status_update()

Enum.each(periodic, fn {name, status} ->
  ready_status = if status.ready?, do: "READY", else: "NOT READY"
  IO.puts("   #{name}: #{ready_status}")

  if Map.has_key?(status, :error) do
    IO.puts("     Error: #{inspect(status.error)}")
  end
end)

# Example 8: Get full dashboard status
IO.puts("\n8. Getting full dashboard status...")
dashboard = StatusMonitor.dashboard_status()
IO.puts("   Timestamp: #{dashboard.timestamp}")
IO.puts("   Client details:")

Enum.each(dashboard.clients, fn {name, client} ->
  IO.puts("     #{name}:")
  IO.puts("       Status: #{client.status}")
  IO.puts("       Alive?: #{client.alive?}")

  if Map.has_key?(client, :pid) do
    IO.puts("       PID: #{inspect(client.pid)}")
  end

  if Map.has_key?(client, :error) do
    IO.puts("       Error: #{inspect(client.error)}")
  end
end)

# Example 9: Simulate a client failure
IO.puts("\n9. Simulating client failure...")
Agent.stop(client2_pid)
Process.sleep(50)

summary = StatusMonitor.health_summary()
IO.puts("   After failure:")
IO.puts("   Healthy: #{length(summary.healthy_clients)}")
IO.puts("   Unhealthy: #{length(summary.unhealthy_clients)}")
IO.puts("   Uptime: #{Float.round(summary.uptime_percentage, 2)}%")

# Example 10: Unregister a client
IO.puts("\n10. Unregistering a client...")
StatusMonitor.unregister_client(:filesystem)
IO.puts("   ✓ Unregistered :filesystem client")
IO.puts("   Remaining clients: #{StatusMonitor.count_clients()}")

IO.puts("\n=== Example Complete ===\n")

# Clean up
StatusMonitor.unregister_client(:github)
Agent.stop(client1_pid)
