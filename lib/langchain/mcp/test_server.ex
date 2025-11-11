defmodule LangChainMCP.TestServer do
  @moduledoc """
  Simple MCP test server for integration testing.

  Provides basic tools similar to the MCP time server for testing purposes.

  ## Usage

  Start the server in your supervision tree or manually:

      {:ok, _pid} = Hermes.Server.Supervisor.start_link(
        LangChainMCP.TestServer,
        transport: :streamable_http,
        streamable_http: [port: 4000]
      )

  Or run from command line:

      mix test_server
  """

  use Hermes.Server,
    name: "Test MCP Server",
    version: "1.0.0",
    capabilities: [:tools]

  require Logger

  @impl true
  def init(client_info, frame) do
    Logger.debug("[#{__MODULE__}] => Initialized MCP connection with #{inspect(client_info)}")

    {:ok,
     frame
     |> assign(counter: 0)
     |> register_tool("get_current_time",
       input_schema: %{
         timezone:
           {:optional, :string, description: "IANA timezone name (e.g., 'America/New_York')"}
       },
       description: "Get the current time in a specified timezone or UTC"
     )
     |> register_tool("get_timestamp",
       input_schema: %{},
       description: "Get the current Unix timestamp"
     )
     |> register_tool("add_numbers",
       input_schema: %{
         a: {:required, :integer, description: "First number"},
         b: {:required, :integer, description: "Second number"}
       },
       description: "Add two numbers together"
     )}
  end

  @impl true
  def handle_tool_call("get_current_time", args, frame) do
    timezone = Map.get(args, :timezone, "UTC")

    result =
      case timezone do
        "UTC" ->
          DateTime.utc_now() |> DateTime.to_iso8601()

        tz ->
          # For simplicity, just return UTC with the requested timezone label
          # In a real implementation, you'd use a timezone library
          "#{DateTime.utc_now() |> DateTime.to_iso8601()} (requested: #{tz})"
      end

    # {:reply, result, frame}
    {:reply, result, assign(frame, counter: frame.assigns.counter + 1)}
  end

  @impl true
  def handle_tool_call("get_timestamp", _args, frame) do
    timestamp = System.system_time(:second)
    {:reply, timestamp, frame}
  end

  @impl true
  def handle_tool_call("add_numbers", %{a: a, b: b}, frame) do
    result = a + b
    {:reply, result, frame}
  end
end
