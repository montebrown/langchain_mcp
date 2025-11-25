defmodule Mix.Tasks.TestServer do
  @moduledoc """
  Starts the MCP test server for integration testing.

  ## Usage

      mix test_server

  Or specify a custom port:

      mix test_server --port 4001

  The server will run on http://localhost:4000 by default and can be used
  with the integration tests via:

      mix test --include live_call
  """

  @shortdoc "Starts the MCP test server"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    # Parse command line options
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [port: :integer],
        aliases: [p: :port]
      )

    port = Keyword.get(opts, :port, 4000)

    # Start the application
    Mix.Task.run("app.start")

    # Ensure required applications are started
    Application.ensure_all_started(:anubis_mcp)
    Application.ensure_all_started(:bandit)

    # Start the Anubis.Server.Registry
    {:ok, _registry_pid} = Anubis.Server.Registry.child_spec([]) |> start_child()

    # Start the MCP server with streamable_http transport (transport layer only, no HTTP server)
    {:ok, _mcp_server_pid} =
      Anubis.Server.Supervisor.start_link(
        LangChainMCP.TestServer,
        transport: {:streamable_http, []}
      )

    # Start the HTTP server with Bandit
    IO.puts("\n🚀 Starting MCP Test Server on http://localhost:#{port}")
    IO.puts("   Tools available: get_current_time, get_timestamp, add_numbers")
    IO.puts("   Endpoints: /sse (SSE connection), /message (POST messages)")
    IO.puts("   Press Ctrl+C to stop\n")

    {:ok, _http_pid} =
      Bandit.start_link(
        plug: LangChainMCP.TestServer.Router,
        port: port,
        scheme: :http
      )

    # Keep the task running
    :timer.sleep(:infinity)
  end

  defp start_child(%{start: {mod, fun, args}}) do
    apply(mod, fun, args)
  end
end
