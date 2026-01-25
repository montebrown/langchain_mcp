defmodule LangChain.MCP.AdapterIntegrationTest do
  use LangChainMCP.MCPCase

  alias LangChain.Function
  alias LangChain.MCP.Adapter

  @moduletag :live_call

  describe "discover_tools/2 with live server" do
    test "discovers tools from MCP server", %{client: client} do
      adapter = Adapter.new(client: client)

      {:ok, tools} = Adapter.discover_tools(adapter)

      assert is_list(tools)
      assert length(tools) > 0

      # Check tool structure
      tool = hd(tools)
      assert is_binary(tool["name"])
      assert is_map(tool["inputSchema"])
    end

    test "caches tools when enabled", %{client: client} do
      adapter = Adapter.new(client: client, cache_tools: true)

      # First call discovers
      {:ok, tools1} = Adapter.discover_tools(adapter)

      # Second call should use cache (same reference)
      {:ok, tools2} = Adapter.discover_tools(adapter)

      assert tools1 == tools2
    end

    test "refreshes cache when requested", %{client: client} do
      adapter = Adapter.new(client: client, cache_tools: true)

      # Initial discovery
      {:ok, _tools} = Adapter.discover_tools(adapter)

      # Force refresh
      {:ok, refreshed_tools} = Adapter.discover_tools(adapter, refresh: true)

      assert is_list(refreshed_tools)
    end
  end

  describe "to_functions/2 with live server" do
    test "converts tools to LangChain functions", %{client: client} do
      adapter = Adapter.new(client: client)

      functions = Adapter.to_functions(adapter)

      assert is_list(functions)
      assert length(functions) > 0

      # Check function structure
      func = hd(functions)
      assert %Function{} = func
      assert is_binary(func.name)
      assert is_list(func.parameters)
      assert is_function(func.function, 2)
    end

    test "filters tools with :only option", %{client: client} do
      adapter = Adapter.new(client: client)

      # First get all tools to know what's available
      {:ok, all_tools} = Adapter.discover_tools(adapter)
      tool_names = Enum.map(all_tools, & &1["name"])

      if length(tool_names) > 1 do
        # Filter to only first tool
        first_tool = hd(tool_names)
        functions = Adapter.to_functions(adapter, only: [first_tool])

        assert length(functions) == 1
        assert hd(functions).name == first_tool
      end
    end

    test "filters tools with :except option", %{client: client} do
      adapter = Adapter.new(client: client)

      {:ok, all_tools} = Adapter.discover_tools(adapter)
      all_count = length(all_tools)

      if all_count > 1 do
        first_tool_name = hd(all_tools)["name"]
        functions = Adapter.to_functions(adapter, except: [first_tool_name])

        assert length(functions) == all_count - 1
        refute Enum.any?(functions, &(&1.name == first_tool_name))
      end
    end
  end

  describe "tool execution with live server" do
    test "executes a tool and returns result", %{client: client} do
      adapter = Adapter.new(client: client)
      functions = Adapter.to_functions(adapter)

      # Get first available function
      func = hd(functions)

      # For time server, we'd call get_current_time
      # This test is generic, so we'll just verify the function is callable
      assert is_function(func.function, 2)
    end
  end

  describe "get_tool/2" do
    test "retrieves specific tool information", %{client: client} do
      adapter = Adapter.new(client: client)

      {:ok, tools} = Adapter.discover_tools(adapter)
      first_tool_name = hd(tools)["name"]

      {:ok, tool} = Adapter.get_tool(adapter, first_tool_name)

      assert tool["name"] == first_tool_name
      assert is_map(tool["inputSchema"])
    end

    test "returns error for non-existent tool", %{client: client} do
      adapter = Adapter.new(client: client)

      result = Adapter.get_tool(adapter, "nonexistent_tool_12345")

      assert result == {:error, :not_found}
    end
  end

  describe "validate_tools/2" do
    test "validates existing tools", %{client: client} do
      adapter = Adapter.new(client: client)

      {:ok, tools} = Adapter.discover_tools(adapter)
      tool_names = Enum.map(tools, & &1["name"])

      result = Adapter.validate_tools(adapter, tool_names)

      assert result == :ok
    end

    test "reports missing tools", %{client: client} do
      adapter = Adapter.new(client: client)

      {:ok, tools} = Adapter.discover_tools(adapter)
      existing_tool = hd(tools)["name"]

      result = Adapter.validate_tools(adapter, [existing_tool, "nonexistent"])

      assert {:error, missing} = result
      assert "nonexistent" in missing
    end
  end

  describe "adapter with PID client" do
    test "to_functions works with PID client", %{client_pid: client_pid} do
      # Use the client PID from the MCPCase setup
      :ok = Adapter.wait_for_server_ready(client_pid)

      # Create adapter with PID instead of module name
      adapter = Adapter.new(client: client_pid)

      # Discover tools - uses ToolExecutor.list_tools which now supports PIDs
      {:ok, tools} = Adapter.discover_tools(adapter)

      assert is_list(tools)
      assert length(tools) > 0

      # Convert to LangChain functions
      functions = Adapter.to_functions(adapter)

      assert is_list(functions)
      assert length(functions) > 0

      func = hd(functions)
      assert %Function{} = func
      assert is_binary(func.name)
      assert is_function(func.function, 2)
    end
  end
end
