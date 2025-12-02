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
end
