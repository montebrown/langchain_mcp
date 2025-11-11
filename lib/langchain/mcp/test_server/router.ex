defmodule LangChainMCP.TestServer.Router do
  @moduledoc false
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  forward("/",
    to: Hermes.Server.Transport.StreamableHTTP.Plug,
    init_opts: [server: LangChainMCP.TestServer]
  )
end
