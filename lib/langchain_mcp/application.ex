defmodule LangChain.MCP.Application do
  @moduledoc """
  Application supervisor for LangChain MCP.

  Starts the Registry used by StatusMonitor to track MCP client status.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: :langchain_mcp_clients}
    ]

    opts = [strategy: :one_for_one, name: LangChain.MCP.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
