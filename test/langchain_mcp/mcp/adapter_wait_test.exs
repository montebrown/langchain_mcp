defmodule LangChain.MCP.AdapterWaitTest do
  use LangChainMCP.MCPCase

  alias LangChain.MCP.Adapter

  describe "wait_for_server_ready/1" do
    test "returns error for invalid client PID" do
      # Create a fake PID that's not a supervisor
      fake_pid = spawn(fn -> :timer.sleep(:infinity) end)

      result = Adapter.wait_for_server_ready(fake_pid, 1_000)

      # Clean up
      Process.exit(fake_pid, :kill)

      assert result == {:error, :invalid_client}
    end

    test "returns error for dead process" do
      # Create a PID that immediately dies
      fake_pid = spawn(fn -> :ok end)
      Process.sleep(10)

      result = Adapter.wait_for_server_ready(fake_pid, 1_000)

      assert result == {:error, :invalid_client}
    end

    test "returns timeout when server doesn't respond" do
      # Define a minimal test client
      defmodule TimeoutTestClient do
        use Anubis.Client,
          name: "TimeoutTestClient",
          version: "1.0.0",
          protocol_version: "2025-03-26"
      end

      # Start client with sleep which won't respond to MCP at all
      # This avoids the issue where cat echoes messages back causing protocol errors
      {:ok, client_pid} =
        TimeoutTestClient.start_link(
          transport: {:stdio, command: "sleep", args: ["infinity"]},
          client_info: %{"name" => "Test", "version" => "1.0.0"},
          capabilities: %{},
          protocol_version: "2025-03-26"
        )

      # Should timeout since sleep doesn't respond at all
      result = Adapter.wait_for_server_ready(client_pid, 500)

      # Clean up
      if Process.alive?(client_pid), do: Supervisor.stop(client_pid)

      assert result == {:error, :initialization_timeout}
    end

    # Note: A live integration test with a real MCP server can be added
    # to test/langchain/mcp/adapter_integration_test.exs if needed

    test "respects custom timeout" do
      # Define a minimal test client
      defmodule CustomTimeoutClient do
        use Anubis.Client,
          name: "CustomTimeoutClient",
          version: "1.0.0",
          protocol_version: "2025-03-26"
      end

      # Start client with sleep (won't respond at all)
      # This avoids the issue where cat echoes messages back causing protocol errors
      {:ok, client_pid} =
        CustomTimeoutClient.start_link(
          transport: {:stdio, command: "sleep", args: ["infinity"]},
          client_info: %{"name" => "Test", "version" => "1.0.0"},
          capabilities: %{},
          protocol_version: "2025-03-26"
        )

      # Test with a very short timeout
      start_time = System.monotonic_time(:millisecond)
      result = Adapter.wait_for_server_ready(client_pid, 200)
      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time

      # Clean up
      if Process.alive?(client_pid), do: Supervisor.stop(client_pid)

      assert result == {:error, :initialization_timeout}
      # Should timeout close to 200ms (allow some overhead)
      assert elapsed >= 200 and elapsed < 400
    end
  end
end
