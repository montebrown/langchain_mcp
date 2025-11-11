#!/usr/bin/env elixir

# Basic usage example for LangChain MCP integration
#
# This example demonstrates how to:
# 1. Define an MCP client
# 2. Create an adapter
# 3. Discover and use MCP tools in a LangChain

Mix.install([
  # {:langchain, path: Path.expand("../../langchain", __DIR__)},
  {:langchain, "~> 0.4.0"},
  {:langchain_mcp, path: Path.expand("..", __DIR__)},
  # {:hermes_mcp, path: Path.expand("../../hermes-mcp", __DIR__)}
  # {:hermes_mcp, path: Path.expand("~/src/hermes-mcp", __DIR__)}
  {:hermes_mcp, path: "~/src/hermes-mcp"},
  {:plug, "~> 1.18.1"},
  # {:hermes_mcp, "~> 0.14"}
])

# Define MCP client that connects to a local MCP server
defmodule Examples.MCPClient do
  use Hermes.Client,
    name: "Examples",
    version: "1.0.0",
    protocol_version: "2025-03-26"
end

# Example 1: Basic Tool Discovery
defmodule Example1.ToolDiscovery do
  alias LangChain.MCP.Adapter

  def run do
    IO.puts("\n=== Example 1: Tool Discovery ===\n")

    # Create adapter
    adapter = Adapter.new(client: Examples.MCPClient)

    # Discover tools
    case Adapter.discover_tools(adapter) do
      {:ok, tools} ->
        IO.puts("Discovered #{length(tools)} tools:")

        Enum.each(tools, fn tool ->
          IO.puts("  - #{tool["name"]}: #{tool["description"]}")
        end)

      {:error, reason} ->
        IO.puts("Failed to discover tools: #{reason}")
    end
  end
end

# Example 2: Convert Tools to LangChain Functions
defmodule Example2.ToolConversion do
  alias LangChain.MCP.Adapter

  def run do
    IO.puts("\n=== Example 2: Tool Conversion ===\n")

    adapter = Adapter.new(client: Examples.MCPClient)

    # Convert to LangChain functions
    functions = Adapter.to_functions(adapter)

    IO.puts("Converted #{length(functions)} functions:")

    Enum.each(functions, fn func ->
      IO.puts("  - #{func.name}")
      IO.puts("    Description: #{func.description}")
      IO.puts("    Parameters: #{length(func.parameters)}")
      IO.puts("    Async: #{func.async}")
    end)
  end
end

# Example 3: Use in LLMChain
defmodule Example3.LLMChainIntegration do
  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message
  alias LangChain.MCP.Adapter

  def run do
    IO.puts("\n=== Example 3: LLMChain Integration ===\n")

    # Create adapter and discover tools
    adapter = Adapter.new(client: Examples.MCPClient)
    mcp_functions = Adapter.to_functions(adapter)

    # Create LLM
    llm = ChatAnthropic.new!(%{
      model: "claude-3-5-sonnet-20241022",
      temperature: 0,
      stream: false
    })

    # Create chain with MCP tools
    chain =
      LLMChain.new!(%{llm: llm})
      |> LLMChain.add_tools(mcp_functions)
      |> LLMChain.add_message(Message.new_system!("You are a helpful assistant."))
      |> LLMChain.add_message(Message.new_user!("What time is it in New York?"))

    # Run chain
    case LLMChain.run(chain, mode: :while_needs_response) do
      {:ok, updated_chain} ->
        last_message = updated_chain.last_message
        IO.puts("Assistant response: #{last_message.content}")

      {:error, _chain, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end
end

# Example 4: With Fallback Client
defmodule Example4.WithFallback do
  alias LangChain.MCP.Adapter
  require Logger

  def run do
    IO.puts("\n=== Example 4: Fallback Configuration ===\n")

    # Create adapter with fallback
    adapter =
      Adapter.new(
        client: Examples.MCPClient,
        fallback_client: Examples.MCPClient,
        # Note: In real usage, fallback would be a different client
        before_fallback: fn _config, tool_name, _args ->
          Logger.warning("Falling back for tool: #{tool_name}")
          :continue
        end
      )

    functions = Adapter.to_functions(adapter)
    IO.puts("Created #{length(functions)} functions with fallback support")
  end
end

# Example 5: Tool Filtering
defmodule Example5.ToolFiltering do
  alias LangChain.MCP.Adapter

  def run do
    IO.puts("\n=== Example 5: Tool Filtering ===\n")

    adapter = Adapter.new(client: Examples.MCPClient)

    # Get all tools first
    {:ok, all_tools} = Adapter.discover_tools(adapter)
    IO.puts("Total tools available: #{length(all_tools)}")

    # Filter with :only
    if length(all_tools) > 0 do
      first_tool = hd(all_tools)["name"]
      filtered = Adapter.to_functions(adapter, only: [first_tool])
      IO.puts("Filtered with :only - #{length(filtered)} function(s)")
    end

    # Custom filter function
    filtered_adapter =
      Adapter.new(
        client: Examples.MCPClient,
        tool_filter: fn tool ->
          # Example: Only allow tools that don't contain "admin"
          not String.contains?(tool["name"], "admin")
        end
      )

    functions = Adapter.to_functions(filtered_adapter)
    IO.puts("Custom filtered: #{length(functions)} function(s)")
  end
end

# Example 6: Configuration Options
defmodule Example6.ConfigurationOptions do
  alias LangChain.MCP.Adapter

  def run do
    IO.puts("\n=== Example 6: Configuration Options ===\n")

    # Configure various options
    adapter =
      Adapter.new(
        client: Examples.MCPClient,
        # Enable caching for performance
        cache_tools: true,
        # Increase timeout for slow operations
        timeout: 60_000,
        # Mark tools as async for parallel execution
        async: true,
        # Pass context that will be available to tools
        context: %{
          user_id: 123,
          session: "abc123"
        }
      )

    config = Adapter.get_config(adapter)

    IO.puts("Configuration:")
    IO.puts("  Cache enabled: #{config.cache_tools}")
    IO.puts("  Timeout: #{config.timeout}ms")
    IO.puts("  Async: #{config.async}")
    IO.puts("  Context: #{inspect(config.context)}")
  end
end

# Main execution
defmodule Examples.Runner do
  def run do
    IO.puts("""
    LangChain MCP Integration Examples
    ===================================

    Note: These examples require a running MCP server.
    Start the test server with: docker-compose up -d

    Press Ctrl+C to exit
    """)

    # Check if server is available
    case :gen_tcp.connect(~c"localhost", 4000, [], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        run_examples()

      {:error, _} ->
        IO.puts("""
        ⚠️  MCP server not available on localhost:4000

        Please start the server:
          docker-compose up -d

        Then run this example again.
        """)
    end
  end

  defp run_examples do


    # Start MCP client
    {:ok, _pid} =
      Examples.MCPClient.start_link(
        client_info: %{"name" => "LangChain MCP", "version" => to_string(Application.spec(:langchain_mcp, :vsn))},
        capabilities: %{"roots" => %{}},
        protocol_version: "2025-06-18",
        transport: {:streamable_http, base_url: "http://localhost:4000"}
      )

    # Run examples
    Example1.ToolDiscovery.run()
    Example2.ToolConversion.run()
    # Example3.LLMChainIntegration.run()  # Requires API key
    Example4.WithFallback.run()
    Example5.ToolFiltering.run()
    Example6.ConfigurationOptions.run()

    IO.puts("\n✓ Examples completed!\n")
  end
end

# Run if executed directly
if System.get_env("MIX_ENV") != "test" do
  Examples.Runner.run()
end
