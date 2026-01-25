defmodule LangChain.MCP.StatusMonitor do
  @moduledoc """
  Monitor and track the status of MCP clients using the Elixir Registry.

  This module provides a lightweight solution for tracking multiple MCP clients
  without requiring additional GenServers. Each client GenServer registers itself
  with the StatusMonitor, which can then be queried for real-time status updates.

  ## Usage

      # Register a client
      {:ok, _} = StatusMonitor.register_client(:my_client, client_pid)

      # Get client status
      {:ok, status} = StatusMonitor.get_client_status(:my_client)

      # Get all clients
      all_clients = StatusMonitor.get_all_clients_status()

      # Health check
      {ping, status} = StatusMonitor.health_check(:my_client)

      # Health summary
      summary = StatusMonitor.health_summary()
  """
  require Logger

  @registry_name :langchain_mcp_clients

  @doc """
  Register a client for status monitoring.

  ## Parameters

    - `name` - Atom name for the client (e.g., `:github_client`)
    - `client_pid` - PID of the client GenServer

  ## Returns

    - `{:ok, :registered}` - Successfully registered
    - `{:ok, :already_registered}` - Client was already registered
  """
  def register_client(name, client_pid) when is_atom(name) and is_pid(client_pid) do
    case Registry.register(@registry_name, name, %{pid: client_pid}) do
      {:ok, _pid} ->
        Logger.info("Registered MCP client #{name} for status monitoring")
        {:ok, :registered}

      {:error, {:already_registered, _}} ->
        Logger.debug("MCP client #{name} already registered")
        {:ok, :already_registered}
    end
  end

  @doc """
  Unregister a client from status monitoring.

  ## Parameters

    - `name` - Atom name of the client to unregister

  ## Returns

    - `:ok`
  """
  def unregister_client(name) when is_atom(name) do
    Registry.unregister(@registry_name, name)
    :ok
  end

  @doc """
  Get the status of a specific client.

  ## Parameters

    - `name` - Atom name of the client

  ## Returns

    - `{:ok, %{pid: pid}}` - Client is registered and available
    - `{:error, :client_not_registered}` - Client is not registered
    - `{:error, {:client_unavailable, reason}}` - Client process is dead
  """
  def get_client_status(name) when is_atom(name) do
    case Registry.lookup(@registry_name, name) do
      [{_pid, %{process_name: process_name}}] ->
        case Process.whereis(process_name) do
          pid when is_pid(pid) ->
            {:ok, %{pid: pid}}

          nil ->
            {:error, {:client_unavailable, :process_dead}}
        end

      [{_pid, %{pid: client_pid}}] ->
        if Process.alive?(client_pid) do
          {:ok, %{pid: client_pid}}
        else
          {:error, {:client_unavailable, :process_dead}}
        end

      [] ->
        {:error, :client_not_registered}
    end
  end

  @doc """
  Get the status of all registered clients.

  ## Returns

    - Map with client names as keys and `{:ok, status}` or `{:error, reason}` as values
  """
  def get_all_clients_status do
    Registry.select(@registry_name, [{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.reduce(%{}, fn name, acc ->
      case get_client_status(name) do
        {:ok, status} -> Map.put(acc, name, {:ok, status})
        {:error, reason} -> Map.put(acc, name, {:error, reason})
      end
    end)
  end

  @doc """
  Perform a health check on a specific client.

  ## Parameters

    - `name` - Atom name of the client

  ## Returns

    - `{ping_result, status_result}` - Tuple with ping and status check results
  """
  def health_check(name) when is_atom(name) do
    case Registry.lookup(@registry_name, name) do
      [{_pid, %{process_name: process_name}}] ->
        ping_result =
          case Process.whereis(process_name) do
            pid when is_pid(pid) -> :pong
            nil -> {:error, :process_dead}
          end

        status_result = get_client_status(name)

        {ping_result, status_result}

      [{_pid, %{pid: client_pid}}] ->
        ping_result =
          if Process.alive?(client_pid) do
            :pong
          else
            {:error, :process_dead}
          end

        status_result = get_client_status(name)

        {ping_result, status_result}

      [] ->
        {{:error, :client_not_found}, {:error, :client_not_registered}}
    end
  end

  @doc """
  Get a summary of all client health statuses.

  ## Returns

    - Map with keys:
      - `:healthy_clients` - List of client names that are healthy
      - `:unhealthy_clients` - List of client names that are unhealthy
      - `:total_clients` - Total number of clients
      - `:uptime_percentage` - Percentage of healthy clients
  """
  def health_summary do
    all_statuses = get_all_clients_status()

    {healthy_count, unhealthy_count} =
      Enum.reduce(all_statuses, {0, 0}, fn {_name, status_result}, {healthy, unhealthy} ->
        case status_result do
          {:ok, _status} -> {healthy + 1, unhealthy}
          {:error, _reason} -> {healthy, unhealthy + 1}
        end
      end)

    total = healthy_count + unhealthy_count

    uptime_percentage =
      if total > 0 do
        healthy_count / total * 100.0
      else
        0.0
      end

    %{
      healthy_clients:
        Enum.filter(all_statuses, fn {_name, result} -> match?({:ok, _}, result) end)
        |> Enum.map(fn {name, _} -> name end),
      unhealthy_clients:
        Enum.filter(all_statuses, fn {_name, result} -> match?({:error, _}, result) end)
        |> Enum.map(fn {name, _} -> name end),
      total_clients: total,
      uptime_percentage: uptime_percentage
    }
  end

  @doc """
  Get a periodic status update for all clients suitable for real-time dashboards.

  Returns a simplified status map indicating whether each client is ready.

  ## Returns

    - Map with client names as keys and status maps as values
      - `%{ready?: true}` - Client is available
      - `%{ready?: false, error: reason}` - Client is unavailable
  """
  def periodic_status_update do
    Registry.select(@registry_name, [{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.reduce(%{}, fn name, acc ->
      case get_client_status(name) do
        {:ok, _status} -> Map.put(acc, name, %{ready?: true})
        {:error, reason} -> Map.put(acc, name, %{ready?: false, error: reason})
      end
    end)
  end

  @doc """
  List all registered client names.

  ## Returns

    - List of atom names of registered clients
  """
  def list_clients do
    Registry.select(@registry_name, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc """
  Get count of registered clients.

  ## Returns

    - Integer count of registered clients
  """
  def count_clients do
    length(list_clients())
  end

  @doc """
  Register a client by module name after it has been started.

  This function waits for a process to be registered under the given module name,
  then registers it with the StatusMonitor. Useful when registering clients from
  an Application module where you need to wait for processes to start.

  ## Parameters

    - `module` - Module name of the client (e.g., `MyApp.GitHubMCP`)
    - `registry_name` - Atom name to register in StatusMonitor (e.g., `:github`)
    - `timeout` - Maximum time to wait in milliseconds (default: 5000)

  ## Returns

    - `{:ok, :registered}` - Successfully registered
    - `{:ok, :already_registered}` - Client was already registered
    - `{:error, :timeout}` - Process didn't start within timeout
    - `{:error, :process_not_found}` - Process not found after timeout

  ## Examples

      # In Application.start/2
      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            {MyApp.GitHubMCP, transport: {:streamable_http, base_url: "http://localhost:5000"}}
          ]

          {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one)

          # Register after starting
          Task.start(fn ->
            StatusMonitor.register_client_by_name(MyApp.GitHubMCP, :github)
          end)

          {:ok, self()}
        end
      end

      # Or wait synchronously
      {:ok, :registered} = StatusMonitor.register_client_by_name(MyApp.GitHubMCP, :github)
  """
  def register_client_by_name(module, registry_name, timeout \\ 5_000)
      when is_atom(module) and is_atom(registry_name) and is_integer(timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_and_register(module, registry_name, deadline)
  end

  defp wait_and_register(module, registry_name, deadline) do
    case Process.whereis(module) do
      pid when is_pid(pid) ->
        # Store the process name for dynamic resolution, not the PID
        case Registry.register(@registry_name, registry_name, %{process_name: module}) do
          {:ok, _pid} ->
            Logger.info("Registered MCP client #{registry_name} (#{module}) for status monitoring")
            {:ok, :registered}

          {:error, {:already_registered, _}} ->
            Logger.debug("MCP client #{registry_name} already registered")
            {:ok, :already_registered}
        end

      nil ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(50)
          wait_and_register(module, registry_name, deadline)
        else
          {:error, :timeout}
        end
    end
  end

  @doc """
  Check if a specific client is registered.

  ## Parameters

    - `name` - Atom name of the client

  ## Returns

    - `true` if registered, `false` otherwise
  """
  def registered?(name) when is_atom(name) do
    case Registry.lookup(@registry_name, name) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  @doc """
  Get detailed status for real-time monitoring dashboards.

  Includes client health, uptime percentage, and detailed error information.

  ## Returns

    - Map with:
      - `:clients` - Map of client name to detailed status
      - `:summary` - Health summary with uptime percentage
      - `:timestamp` - Current timestamp
  """
  def dashboard_status do
    clients =
      Registry.select(@registry_name, [{{:"$1", :_, :_}, [], [:"$1"]}])
      |> Enum.reduce(%{}, fn name, acc ->
        status =
          case get_client_status(name) do
            {:ok, %{pid: pid}} ->
              %{
                status: :healthy,
                pid: pid,
                alive?: true
              }

            {:error, {:client_unavailable, reason}} ->
              %{
                status: :unhealthy,
                error: reason,
                alive?: false
              }

            {:error, reason} ->
              %{
                status: :error,
                error: reason,
                alive?: false
              }
          end

        Map.put(acc, name, status)
      end)

    summary = health_summary()

    %{
      clients: clients,
      summary: summary,
      timestamp: System.system_time(:millisecond)
    }
  end
end
