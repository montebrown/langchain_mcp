defmodule LangChain.MCP.Client do
  @moduledoc """
  Wrapper for creating MCP clients that decouples from Anubis.Client.

  This module wraps `Anubis.Client` to decouple your application from the
  underlying MCP implementation.

  ## Usage

      defmodule MyApp.GitHubMCP do
        use LangChain.MCP.Client,
          name: "GitHub MCP",
          version: "1.0.0",
          protocol_version: "2025-03-26"
      end

      # Start the client
      {:ok, pid} = MyApp.GitHubMCP.start_link(
        transport: {:streamable_http, base_url: "http://localhost:5000"}
      )

  ## StatusMonitor Integration

  To monitor client health with `LangChain.MCP.StatusMonitor`, register clients
  from your Application module:

      defmodule MyApp.Application do
        use Application
        alias LangChain.MCP.StatusMonitor

        def start(_type, _args) do
          children = [
            {MyApp.GitHubMCP,
              transport: {:streamable_http, base_url: "http://localhost:5000"}}
          ]

          {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one)

          # Register clients for status monitoring
          StatusMonitor.register_client_by_name(MyApp.GitHubMCP, :github)

          {:ok, self()}
        end
      end

  See `LangChain.MCP.StatusMonitor` for more details on monitoring.
  """

  defmacro __before_compile__(_env) do
    quote do
      # Make start_link overridable so we can replace Anubis.Client's version
      defoverridable start_link: 1

      # Override start_link to merge inherited opts
      # This runs after use Anubis.Client, so it will replace Anubis.Client's start_link
      def start_link(opts) when is_list(opts) do
        merged_opts = Keyword.merge(@__inherited_opts__, opts)
        Anubis.Client.Supervisor.start_link(__MODULE__, merged_opts)
      end
    end
  end

  defmacro __using__(opts) do
    # Extract compile-time values that Anubis.Client uses
    name = Keyword.fetch!(opts, :name)
    version = Keyword.fetch!(opts, :version)
    protocol_version = Keyword.fetch!(opts, :protocol_version)

    capabilities =
      Enum.reduce(opts[:capabilities] || [], %{}, fn {k, v}, acc ->
        Map.put(acc, k, v)
      end)

    client_info = %{"name" => name, "version" => version}

    quote location: :keep do
      use Anubis.Client, unquote(opts)

      # Register the @before_compile callback to override start_link after all other code
      @before_compile LangChain.MCP.Client

      # Store inherited values for use in overrides
      @__inherited_opts__ [
        client_info: unquote(Macro.escape(client_info)),
        capabilities: unquote(Macro.escape(capabilities)),
        protocol_version: unquote(protocol_version)
      ]

      # Override child_spec (Anubis.Client already made it overridable)
      # This fixes the merge order so user opts override inherited values
      def child_spec(opts) do
        merged_opts = Keyword.merge(@__inherited_opts__, opts)

        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [merged_opts]},
          type: :supervisor,
          restart: :permanent
        }
      end
    end
  end
end
