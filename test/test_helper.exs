# Ensure dependencies are started
Application.ensure_all_started(:anubis_mcp)

# Start the LangChain.MCP application to ensure Registry is available
Application.ensure_all_started(:langchain_mcp)

# Define the MCP test client for live tests
defmodule LangChainMCP.TestClient do
  @moduledoc """
  Test MCP client for integration tests.

  Connects to a local MCP server (via Docker) for live testing.
  """
  use LangChain.MCP.Client,
    name: "LangChainMCP Test",
    version: "0.1.0",
    protocol_version: "2025-03-26"
end

ExUnit.start()
