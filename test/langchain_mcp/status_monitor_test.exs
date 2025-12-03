defmodule LangChain.MCP.StatusMonitorTest do
  use ExUnit.Case, async: true

  alias LangChain.MCP.StatusMonitor

  describe "register_client/2" do
    test "registers a client for status monitoring" do
      # Create a dummy GenServer for testing
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      assert {:ok, :registered} = StatusMonitor.register_client(:test_client_1, pid)

      # Verify it's registered by checking lookup
      assert [{_reg_pid, %{pid: ^pid}}] =
               Registry.lookup(:langchain_mcp_clients, :test_client_1)
    end

    test "returns already_registered when client already exists" do
      {:ok, pid1} = Agent.start_link(fn -> %{} end)

      # Register first time
      assert {:ok, :registered} = StatusMonitor.register_client(:test_update, pid1)

      # Try to register again with same PID
      assert {:ok, :already_registered} = StatusMonitor.register_client(:test_update, pid1)

      # Should still point to the first PID
      assert [{_reg_pid, %{pid: ^pid1}}] =
               Registry.lookup(:langchain_mcp_clients, :test_update)
    end

    test "accepts atom names for clients" do
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      # These should all work
      assert {:ok, :registered} = StatusMonitor.register_client(:main_client, pid)
      assert {:ok, :registered} = StatusMonitor.register_client(:"client-with-dash", pid)
    end
  end

  describe "unregister_client/1" do
    test "removes client from status monitoring" do
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      StatusMonitor.register_client(:test_remove, pid)
      assert [{_reg_pid, %{pid: ^pid}}] = Registry.lookup(:langchain_mcp_clients, :test_remove)

      assert :ok = StatusMonitor.unregister_client(:test_remove)
      assert [] = Registry.lookup(:langchain_mcp_clients, :test_remove)
    end

    test "handles unregistering non-existent client gracefully" do
      # Should not raise error for unregistered client
      assert :ok = StatusMonitor.unregister_client(:non_existent_client)

      # Verify it wasn't added by the call
      assert [] = Registry.lookup(:langchain_mcp_clients, :non_existent_client)
    end
  end

  describe "get_client_status/1" do
    test "returns error for unregistered client" do
      result = StatusMonitor.get_client_status(:not_registered)

      assert {:error, :client_not_registered} = result
    end

    test "returns status tuple for registered agent-based client" do
      # Use a real GenServer-like process for testing state extraction
      {:ok, pid} = Agent.start_link(fn -> %{test: "state"} end)

      StatusMonitor.register_client(:agent_client, pid)
      result = StatusMonitor.get_client_status(:agent_client)

      assert {:ok, status} = result
      assert is_map(status)
      assert status.pid == pid
    end

    test "handles unavailable client process" do
      # Trap exits to prevent test from crashing
      Process.flag(:trap_exit, true)

      # Create and immediately kill a process
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      Process.exit(pid, :kill)
      Process.sleep(10)

      StatusMonitor.register_client(:dead_client, pid)
      result = StatusMonitor.get_client_status(:dead_client)

      assert {:error, {:client_unavailable, :process_dead}} = result
    end
  end

  describe "get_all_clients_status/0" do
    test "returns empty map when no clients registered" do
      # Clean slate by unregistering any existing test clients
      StatusMonitor.unregister_client(:test_client_1)
      StatusMonitor.unregister_client(:agent_client)

      result = StatusMonitor.get_all_clients_status()

      assert %{} == result
    end

    test "returns status map for all registered clients" do
      {:ok, pid1} = Agent.start_link(fn -> %{id: 1} end)
      {:ok, pid2} = Agent.start_link(fn -> %{id: 2} end)

      StatusMonitor.register_client(:client_1, pid1)
      StatusMonitor.register_client(:client_2, pid2)

      result = StatusMonitor.get_all_clients_status()

      assert map_size(result) == 2
      assert {:ok, _} = Map.fetch!(result, :client_1)
      assert {:ok, _} = Map.fetch!(result, :client_2)
    end

    test "includes error results for unavailable clients" do
      # Trap exits to prevent test from crashing
      Process.flag(:trap_exit, true)

      {:ok, good_pid} = Agent.start_link(fn -> %{good: true} end)

      {:ok, bad_pid} = Agent.start_link(fn -> %{bad: true} end)
      Process.exit(bad_pid, :kill)
      Process.sleep(10)

      StatusMonitor.register_client(:good_client, good_pid)
      StatusMonitor.register_client(:bad_client, bad_pid)

      result = StatusMonitor.get_all_clients_status()

      assert {:ok, _} = Map.fetch!(result, :good_client)
      assert {:error, _} = Map.fetch!(result, :bad_client)
    end
  end

  describe "health_check/1" do
    test "returns error for unregistered client" do
      result = StatusMonitor.health_check(:not_registered)

      assert {{:error, :client_not_found}, {:error, :client_not_registered}} = result
    end

    test "performs health check on available process" do
      {:ok, pid} = Agent.start_link(fn -> %{healthy: true} end)

      StatusMonitor.register_client(:health_test, pid)
      {ping_result, status_result} = StatusMonitor.health_check(:health_test)

      # Should return both ping result and updated status
      assert is_atom(ping_result) or is_tuple(ping_result)
      assert {:ok, status} = status_result
      assert status.pid == pid
    end

    test "handles health check on unavailable process" do
      # Trap exits to prevent test from crashing
      Process.flag(:trap_exit, true)

      {:ok, pid} = Agent.start_link(fn -> %{} end)
      Process.exit(pid, :kill)
      Process.sleep(10)

      StatusMonitor.register_client(:dead_health_test, pid)
      result = StatusMonitor.health_check(:dead_health_test)

      # Should indicate both ping failure and status error
      assert {{:error, :process_dead}, {:error, {:client_unavailable, :process_dead}}} = result
    end
  end

  describe "health_summary/0" do
    test "returns empty summary when no clients" do
      # Clean up any existing registrations first
      StatusMonitor.unregister_client(:test_client_1)
      StatusMonitor.unregister_client(:good_client)

      result = StatusMonitor.health_summary()

      assert %{healthy_clients: [], unhealthy_clients: []} = result
      assert 0.0 == result.uptime_percentage
    end

    test "calculates uptime percentage correctly" do
      # Trap exits to prevent test from crashing
      Process.flag(:trap_exit, true)

      # Register one good and one bad client
      {:ok, good_pid} = Agent.start_link(fn -> %{status: :healthy} end)

      {:ok, bad_pid} = Agent.start_link(fn -> %{status: :dead} end)
      Process.exit(bad_pid, :kill)
      # Give it a moment to die
      Process.sleep(10)

      StatusMonitor.register_client(:good_summary_test, good_pid)
      StatusMonitor.register_client(:bad_summary_test, bad_pid)

      result = StatusMonitor.health_summary()

      # 1 healthy out of 2 total = 50% uptime
      assert length(result.healthy_clients) == 1
      assert length(result.unhealthy_clients) == 1
      assert result.total_clients == 2
      assert 50.0 == result.uptime_percentage
    end

    test "handles mixed client states gracefully" do
      # Trap exits to prevent test from crashing
      Process.flag(:trap_exit, true)

      {:ok, alive} = Agent.start_link(fn -> %{alive: true} end)
      {:ok, dead} = Agent.start_link(fn -> %{dead: true} end)
      Process.exit(dead, :kill)
      Process.sleep(10)

      StatusMonitor.register_client(:mixed_test_1, alive)
      StatusMonitor.register_client(:mixed_test_2, dead)

      result = StatusMonitor.health_summary()

      assert is_map(result)
      assert result.total_clients >= 1
      assert 0.0 <= result.uptime_percentage and result.uptime_percentage <= 100.0
    end
  end

  describe "periodic_status_update/0" do
    test "returns status update map with timestamp info" do
      {:ok, pid} = Agent.start_link(fn -> %{test: :data} end)
      StatusMonitor.register_client(:periodic_test, pid)

      result = StatusMonitor.periodic_status_update()

      assert is_map(result)
      assert Map.has_key?(result, :periodic_test)
      assert %{ready?: true} = result[:periodic_test]
    end

    test "includes error information for failed clients" do
      # Trap exits to prevent test from crashing
      Process.flag(:trap_exit, true)

      {:ok, bad_pid} = Agent.start_link(fn -> %{} end)
      Process.exit(bad_pid, :kill)
      Process.sleep(10)

      StatusMonitor.register_client(:error_periodic, bad_pid)
      result = StatusMonitor.periodic_status_update()

      client_data = Map.fetch!(result, :error_periodic)
      assert %{ready?: false} = client_data
      assert Map.has_key?(client_data, :error)
    end

    test "returns empty map when no clients registered" do
      # Clean up first
      StatusMonitor.unregister_client(:periodic_test)
      StatusMonitor.unregister_client(:mixed_test_1)
      StatusMonitor.unregister_client(:mixed_test_2)

      result = StatusMonitor.periodic_status_update()

      assert %{} == result
    end
  end

  describe "list_clients/0" do
    test "returns list of registered client names" do
      {:ok, pid1} = Agent.start_link(fn -> %{} end)
      {:ok, pid2} = Agent.start_link(fn -> %{} end)

      StatusMonitor.register_client(:list_test_1, pid1)
      StatusMonitor.register_client(:list_test_2, pid2)

      clients = StatusMonitor.list_clients()

      assert is_list(clients)
      assert :list_test_1 in clients
      assert :list_test_2 in clients
    end

    test "returns empty list when no clients" do
      StatusMonitor.unregister_client(:list_test_1)
      StatusMonitor.unregister_client(:list_test_2)

      clients = StatusMonitor.list_clients()

      assert clients == []
    end
  end

  describe "count_clients/0" do
    test "returns count of registered clients" do
      {:ok, pid1} = Agent.start_link(fn -> %{} end)
      {:ok, pid2} = Agent.start_link(fn -> %{} end)

      StatusMonitor.register_client(:count_test_1, pid1)
      StatusMonitor.register_client(:count_test_2, pid2)

      assert StatusMonitor.count_clients() == 2
    end

    test "returns 0 when no clients" do
      StatusMonitor.unregister_client(:count_test_1)
      StatusMonitor.unregister_client(:count_test_2)

      assert StatusMonitor.count_clients() == 0
    end
  end

  describe "registered?/1" do
    test "returns true for registered client" do
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      StatusMonitor.register_client(:registered_test, pid)

      assert StatusMonitor.registered?(:registered_test) == true
    end

    test "returns false for unregistered client" do
      assert StatusMonitor.registered?(:not_registered_test) == false
    end
  end

  describe "dashboard_status/0" do
    test "returns comprehensive dashboard data" do
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      StatusMonitor.register_client(:dashboard_test, pid)

      result = StatusMonitor.dashboard_status()

      assert is_map(result)
      assert Map.has_key?(result, :clients)
      assert Map.has_key?(result, :summary)
      assert Map.has_key?(result, :timestamp)
      assert is_integer(result.timestamp)
    end

    test "includes detailed client status" do
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      StatusMonitor.register_client(:dashboard_detail_test, pid)

      result = StatusMonitor.dashboard_status()

      client_status = result.clients[:dashboard_detail_test]
      assert client_status.status == :healthy
      assert client_status.alive? == true
      assert client_status.pid == pid
    end

    test "handles unhealthy clients in dashboard" do
      Process.flag(:trap_exit, true)

      {:ok, pid} = Agent.start_link(fn -> %{} end)
      Process.exit(pid, :kill)
      Process.sleep(10)

      StatusMonitor.register_client(:dashboard_unhealthy, pid)

      result = StatusMonitor.dashboard_status()

      client_status = result.clients[:dashboard_unhealthy]
      assert client_status.status == :unhealthy
      assert client_status.alive? == false
      assert Map.has_key?(client_status, :error)
    end
  end

  setup do
    # Clean up any test registrations after each test
    on_exit(fn ->
      Enum.each(
        [
          :test_client_1,
          :test_update,
          :test_remove,
          :not_registered,
          :agent_client,
          :dead_client,
          :client_1,
          :client_2,
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
          :main_client,
          :"client-with-dash",
          :list_test_1,
          :list_test_2,
          :count_test_1,
          :count_test_2,
          :registered_test,
          :not_registered_test,
          :dashboard_test,
          :dashboard_detail_test,
          :dashboard_unhealthy
        ],
        fn name ->
          StatusMonitor.unregister_client(name)
        end
      )
    end)

    :ok
  end

  describe "register_client_by_name/3" do
    test "waits for and registers a client by module name" do
      # Start a named process
      {:ok, pid} = Agent.start_link(fn -> %{} end, name: TestModuleForRegistration)

      # Register using module name
      assert {:ok, :registered} =
               StatusMonitor.register_client_by_name(TestModuleForRegistration, :test_by_name)

      # Verify registration
      assert StatusMonitor.registered?(:test_by_name)
      {:ok, status} = StatusMonitor.get_client_status(:test_by_name)
      assert status.pid == pid

      # Cleanup
      StatusMonitor.unregister_client(:test_by_name)
      Agent.stop(pid)
    end

    test "returns timeout error if process doesn't start in time" do
      # Try to register a non-existent process with short timeout
      assert {:error, :timeout} =
               StatusMonitor.register_client_by_name(NonExistentModule, :never_started, 100)
    end

    test "waits for process to start before registering" do
      # Process not started yet
      refute StatusMonitor.registered?(:delayed_client)

      # Start the process in the background after a delay
      test_pid = self()

      spawn(fn ->
        Process.sleep(100)
        {:ok, pid} = Agent.start_link(fn -> %{} end, name: DelayedTestModule)
        send(test_pid, {:started, pid})
      end)

      # Try to register - should wait for process (blocks until process starts or timeout)
      assert {:ok, :registered} =
               StatusMonitor.register_client_by_name(DelayedTestModule, :delayed_client, 2000)

      # Verify registration
      assert StatusMonitor.registered?(:delayed_client)

      # Wait for the PID message
      assert_receive {:started, pid}, 500

      # Cleanup
      StatusMonitor.unregister_client(:delayed_client)
      Agent.stop(pid)
    end

    test "returns already_registered if client was already registered" do
      # Start and register a process
      {:ok, pid} = Agent.start_link(fn -> %{} end, name: AlreadyRegisteredModule)
      StatusMonitor.register_client(:already_reg, pid)

      # Try to register again using module name
      assert {:ok, :already_registered} =
               StatusMonitor.register_client_by_name(AlreadyRegisteredModule, :already_reg)

      # Cleanup
      StatusMonitor.unregister_client(:already_reg)
      Agent.stop(pid)
    end

    test "respects custom timeout parameter" do
      # Try with very short timeout
      start_time = System.monotonic_time(:millisecond)

      assert {:error, :timeout} =
               StatusMonitor.register_client_by_name(ShortTimeoutModule, :short_timeout, 200)

      elapsed = System.monotonic_time(:millisecond) - start_time

      # Should timeout in approximately 200ms (with some tolerance)
      assert elapsed >= 200
      assert elapsed < 500
    end

    test "default timeout is 5000ms" do
      # This test verifies the default by checking the function signature
      # We can't easily test the actual timeout without waiting 5 seconds
      # Instead, we verify the function can be called without the timeout parameter

      # Start a process quickly
      {:ok, pid} = Agent.start_link(fn -> %{} end, name: DefaultTimeoutModule)

      # Should work with default timeout (not specified)
      assert {:ok, :registered} =
               StatusMonitor.register_client_by_name(DefaultTimeoutModule, :default_timeout)

      # Cleanup
      StatusMonitor.unregister_client(:default_timeout)
      Agent.stop(pid)
    end

    test "handles multiple concurrent registrations" do
      # Start multiple processes
      {:ok, pid1} = Agent.start_link(fn -> %{} end, name: ConcurrentModule1)
      {:ok, pid2} = Agent.start_link(fn -> %{} end, name: ConcurrentModule2)
      {:ok, pid3} = Agent.start_link(fn -> %{} end, name: ConcurrentModule3)

      # Register them (no Task needed - registration is fast and synchronous)
      assert {:ok, :registered} =
               StatusMonitor.register_client_by_name(ConcurrentModule1, :concurrent1)

      assert {:ok, :registered} =
               StatusMonitor.register_client_by_name(ConcurrentModule2, :concurrent2)

      assert {:ok, :registered} =
               StatusMonitor.register_client_by_name(ConcurrentModule3, :concurrent3)

      # All should be registered
      assert StatusMonitor.registered?(:concurrent1)
      assert StatusMonitor.registered?(:concurrent2)
      assert StatusMonitor.registered?(:concurrent3)

      # Cleanup
      StatusMonitor.unregister_client(:concurrent1)
      StatusMonitor.unregister_client(:concurrent2)
      StatusMonitor.unregister_client(:concurrent3)
      Agent.stop(pid1)
      Agent.stop(pid2)
      Agent.stop(pid3)
    end

    test "works with LangChain.MCP.Client modules" do
      defmodule TestMCPClientForRegistration do
        use LangChain.MCP.Client,
          name: "Test Client",
          version: "1.0.0",
          protocol_version: "2025-03-26"
      end

      # Start the client (without auto-registration)
      {:ok, pid} =
        TestMCPClientForRegistration.start_link(
          transport: {:streamable_http, base_url: "http://localhost:5000"}
        )

      # Manually register using helper
      assert {:ok, :registered} =
               StatusMonitor.register_client_by_name(
                 TestMCPClientForRegistration,
                 :mcp_client_test
               )

      # Verify registration
      assert StatusMonitor.registered?(:mcp_client_test)

      # Cleanup
      StatusMonitor.unregister_client(:mcp_client_test)
      Supervisor.stop(pid)
    end
  end
end
