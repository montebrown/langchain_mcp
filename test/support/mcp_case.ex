defmodule LangChainMCP.MCPCase do
  @moduledoc """
  Test case template for MCP integration tests.

  Provides common setup and helpers for testing MCP functionality.

  ## Usage

      defmodule MyTest do
        use LangChainMCP.MCPCase

        @tag :live_call
        test "with real MCP server" do
          # Test will only run with --include live_call
        end
      end
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import LangChainMCP.MCPCase
      alias LangChainMCP.TestClient

      # Automatically cleanup status monitor clients after each test
      setup do
        on_exit(&LangChainMCP.MCPCase.cleanup_status_monitor_clients/0)
        :ok
      end
    end
  end

  setup tags do
    if tags[:live_call] do
      # Start test client for live tests
      case start_test_client() do
        {:ok, pid} ->
          {:ok, client: LangChainMCP.TestClient, client_pid: pid}

        {:error, reason} ->
          IO.puts("""

          Failed to start MCP test client: #{inspect(reason)}

          To run live tests:
          1. Start Docker MCP server: docker-compose up -d
          2. Run tests: mix test --include live_call
          """)

          {:ok, skip: true}
      end
    else
      :ok
    end
  end

  @doc """
  Starts the MCP test client connected to localhost.
  """
  def start_test_client do
    base_url = System.get_env("MCP_TEST_URL", "http://localhost:5000")

    start_supervised(
      {LangChainMCP.TestClient,
       [
         client_info: %{
           "name" => "LangChain MCP",
           "version" => to_string(Application.spec(:langchain_mcp, :vsn))
         },
         capabilities: %{"roots" => %{}},
         protocol_version: "2025-06-18",
         transport: {:streamable_http, base_url: base_url},
         name: :test_mcp_client
       ]}
    )
  end

  @doc """
  Checks if MCP test server is available.
  """
  def server_available? do
    case :gen_tcp.connect(~c"localhost", 5000, [], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  @doc """
  Comprehensive cleanup of all StatusMonitor test clients.

  This function unregisters ALL client names that might be registered during testing,
  preventing test bleed between different test cases.
  """
  def cleanup_status_monitor_clients do
    alias LangChain.MCP.StatusMonitor

    # All possible client names used across tests
    test_client_names = [
      :test_client_1,
      :test_update,
      :main_client,
      :"client-with-dash",
      :test_remove,
      :non_existent_client,
      :agent_client,
      :dead_client,
      :not_registered,
      :good_client,
      :bad_client,
      :health_test,
      :dead_health_test,
      :good_summary_test,
      :bad_summary_test,
      :mixed_test_1,
      :mixed_test_2,
      :non_existent,
      :periodic_test,
      :error_periodic,
      :list_test_1,
      :list_test_2,
      :count_test_1,
      :count_test_2,
      :registered_test,
      :not_registered_test,
      :dashboard_test,
      :dashboard_detail_test,
      :dashboard_unhealthy,
      :test_by_name,
      :never_started,
      :delayed_client,
      :already_reg,
      :short_timeout,
      :default_timeout,
      :concurrent1,
      :concurrent2,
      :concurrent3,
      :mcp_client_test
    ]

    Enum.each(test_client_names, &StatusMonitor.unregister_client(&1))
  end
end
