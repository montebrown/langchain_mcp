defmodule LangChain.MCP.Adapter do
  @moduledoc """
  Main adapter for integrating MCP tools with LangChain.

  This module provides the primary API for discovering MCP tools and converting
  them to LangChain Functions that can be used in LLMChains.

  ## Features

  - Tool discovery from MCP servers
  - Automatic schema conversion
  - Tool caching for performance
  - Tool filtering
  - Fallback client support
  - Async execution configuration

  ## Usage

      # Define MCP client
      defmodule MyApp.MCPClient do
        use Hermes.Client,
          name: "MyApp",
          version: "1.0.0",
          protocol_version: "2025-03-26"
      end

      # Create adapter
      adapter = Adapter.new(client: MyApp.MCPClient)

      # Discover and convert tools
      functions = Adapter.to_functions(adapter)

      # Use in LLMChain
      chain = LLMChain.new!(%{llm: model})
        |> LLMChain.add_tools(functions)
        |> LLMChain.run(mode: :while_needs_response)

  ## With Options

      adapter = Adapter.new(
        client: MyApp.MCPClient,
        cache_tools: true,
        timeout: 60_000,
        async: true,
        fallback_client: MyApp.BackupMCP,
        tool_filter: fn tool -> tool["name"] != "admin_only" end
      )
  """

  alias LangChain.Function
  alias LangChain.MCP.{Config, SchemaConverter, ToolExecutor}
  require Logger

  @type t :: %__MODULE__{
          config: Config.t(),
          cached_tools: [map()] | nil
        }

  defstruct [:config, :cached_tools]

  @doc """
  Creates a new MCP adapter.

  ## Options

  See `LangChain.MCP.Config.new!/1` for all available options.

  ## Examples

      iex> adapter = Adapter.new(client: MyApp.MCPClient)
      %Adapter{config: %Config{...}}

      iex> adapter = Adapter.new(
      ...>   client: MyApp.MCPClient,
      ...>   cache_tools: true,
      ...>   timeout: 60_000,
      ...>   async: true
      ...> )
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    config = Config.new!(opts)

    %__MODULE__{
      config: config,
      cached_tools: nil
    }
  end

  @doc """
  Discovers tools from the MCP server and converts them to LangChain Functions.

  ## Parameters

    * `adapter` - Adapter struct
    * `opts` - Optional keyword list
      * `:only` - List of tool names to include
      * `:except` - List of tool names to exclude
      * `:refresh` - Force refresh cached tools (default: false)

  ## Returns

    * List of `LangChain.Function.t()` structs

  ## Examples

      # Get all tools
      functions = Adapter.to_functions(adapter)

      # Get specific tools
      functions = Adapter.to_functions(adapter, only: ["search", "fetch"])

      # Exclude tools
      functions = Adapter.to_functions(adapter, except: ["admin_tool"])

      # Force refresh cache
      functions = Adapter.to_functions(adapter, refresh: true)
  """
  @spec to_functions(t(), keyword()) :: [Function.t()]
  def to_functions(%__MODULE__{} = adapter, opts \\ []) do
    with {:ok, tools} <- discover_tools(adapter, opts),
         filtered_tools <- apply_filters(adapter, tools, opts) do
      Enum.map(filtered_tools, &tool_to_function(adapter, &1))
    else
      {:error, reason} ->
        Logger.error("Failed to discover MCP tools: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Discovers tools from the MCP server without converting to Functions.

  Useful for inspecting available tools.

  ## Parameters

    * `adapter` - Adapter struct
    * `opts` - Options (`:refresh` to force cache refresh)

  ## Returns

    * `{:ok, tools}` - List of tool maps
    * `{:error, reason}` - Error message

  ## Examples

      iex> {:ok, tools} = Adapter.discover_tools(adapter)
      iex> Enum.map(tools, & &1["name"])
      ["search", "fetch", "analyze"]
  """
  @spec discover_tools(t(), keyword()) :: {:ok, [map()]} | {:error, String.t()}
  def discover_tools(%__MODULE__{config: config, cached_tools: cached}, opts \\ []) do
    refresh = Keyword.get(opts, :refresh, false)

    cond do
      # Use cache if available and not forcing refresh
      config.cache_tools && !refresh && cached != nil ->
        {:ok, cached}

      # Discover from server
      true ->
        case ToolExecutor.list_tools(config.client) do
          {:ok, tools} ->
            # Update cache if caching enabled
            if config.cache_tools do
              # Note: This doesn't actually update the struct in place.
              # Caller should use the returned tools or call to_functions again
              {:ok, tools}
            else
              {:ok, tools}
            end

          error ->
            error
        end
    end
  end

  @doc """
  Converts a single MCP tool to a LangChain Function.

  ## Parameters

    * `adapter` - Adapter struct
    * `tool` - MCP tool map

  ## Returns

    * `LangChain.Function.t()` struct

  ## Examples

      iex> tool = %{
      ...>   "name" => "search",
      ...>   "description" => "Search for information",
      ...>   "inputSchema" => %{
      ...>     "type" => "object",
      ...>     "properties" => %{"query" => %{"type" => "string"}},
      ...>     "required" => ["query"]
      ...>   }
      ...> }
      iex> function = Adapter.tool_to_function(adapter, tool)
      iex> function.name
      "search"
  """
  @spec tool_to_function(t(), map()) :: Function.t()
  def tool_to_function(%__MODULE__{config: config} = _adapter, tool) do
    # Convert inputSchema to FunctionParam list
    input_schema = tool["inputSchema"] || %{}
    parameters = SchemaConverter.to_parameters(input_schema)

    # Create execution function
    tool_name = tool["name"]

    execution_fn = fn args, context ->
      case ToolExecutor.execute(config, tool_name, args, context) do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    end

    # Create Function struct
    Function.new!(%{
      name: tool_name,
      description: tool["description"],
      parameters: parameters,
      function: execution_fn,
      async: config.async
    })
  end

  @doc """
  Refreshes the tool cache for an adapter.

  Only useful if caching is enabled.

  ## Parameters

    * `adapter` - Adapter struct

  ## Returns

    * `{:ok, updated_adapter}` - Adapter with refreshed cache
    * `{:error, reason}` - Error message

  ## Examples

      iex> {:ok, updated_adapter} = Adapter.refresh_cache(adapter)
  """
  @spec refresh_cache(t()) :: {:ok, t()} | {:error, String.t()}
  def refresh_cache(%__MODULE__{config: config} = adapter) do
    case ToolExecutor.list_tools(config.client) do
      {:ok, tools} ->
        {:ok, %{adapter | cached_tools: tools}}

      error ->
        error
    end
  end

  @doc """
  Validates that all required tools are available on the MCP server.

  ## Parameters

    * `adapter` - Adapter struct
    * `tool_names` - List of required tool names

  ## Returns

    * `:ok` - All tools available
    * `{:error, missing_tools}` - List of missing tool names

  ## Examples

      iex> Adapter.validate_tools(adapter, ["search", "fetch"])
      :ok

      iex> Adapter.validate_tools(adapter, ["search", "nonexistent"])
      {:error, ["nonexistent"]}
  """
  @spec validate_tools(t(), [String.t()]) :: :ok | {:error, [String.t()]}
  def validate_tools(%__MODULE__{} = adapter, required_tool_names)
      when is_list(required_tool_names) do
    case discover_tools(adapter) do
      {:ok, tools} ->
        available_names = Enum.map(tools, & &1["name"])
        missing = Enum.reject(required_tool_names, &(&1 in available_names))

        if Enum.empty?(missing) do
          :ok
        else
          {:error, missing}
        end

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Gets information about a specific tool.

  ## Parameters

    * `adapter` - Adapter struct
    * `tool_name` - Name of the tool

  ## Returns

    * `{:ok, tool}` - Tool map
    * `{:error, :not_found}` - Tool not found

  ## Examples

      iex> {:ok, tool} = Adapter.get_tool(adapter, "search")
      iex> tool["description"]
      "Search for information"
  """
  @spec get_tool(t(), String.t()) :: {:ok, map()} | {:error, :not_found | String.t()}
  def get_tool(%__MODULE__{} = adapter, tool_name) when is_binary(tool_name) do
    case discover_tools(adapter) do
      {:ok, tools} ->
        case Enum.find(tools, &(&1["name"] == tool_name)) do
          nil -> {:error, :not_found}
          tool -> {:ok, tool}
        end

      error ->
        error
    end
  end

  # Apply filters to tool list
  defp apply_filters(adapter, tools, opts) do
    tools
    |> apply_only_filter(opts)
    |> apply_except_filter(opts)
    |> apply_custom_filter(adapter)
  end

  defp apply_only_filter(tools, opts) do
    case Keyword.get(opts, :only) do
      nil ->
        tools

      only_list when is_list(only_list) ->
        Enum.filter(tools, &(&1["name"] in only_list))
    end
  end

  defp apply_except_filter(tools, opts) do
    case Keyword.get(opts, :except) do
      nil ->
        tools

      except_list when is_list(except_list) ->
        Enum.reject(tools, &(&1["name"] in except_list))
    end
  end

  defp apply_custom_filter(tools, %__MODULE__{config: config}) do
    if config.tool_filter do
      Enum.filter(tools, &Config.filter_tool?(config, &1))
    else
      tools
    end
  end

  @doc """
  Returns the adapter's configuration.

  ## Examples

      iex> config = Adapter.get_config(adapter)
      iex> config.client
      MyApp.MCPClient
  """
  @spec get_config(t()) :: Config.t()
  def get_config(%__MODULE__{config: config}), do: config

  @doc """
  Updates the adapter's configuration.

  ## Parameters

    * `adapter` - Adapter struct
    * `updates` - Keyword list of config updates

  ## Returns

    * Updated adapter

  ## Examples

      iex> updated = Adapter.update_config(adapter, timeout: 60_000, async: true)
      iex> updated.config.timeout
      60_000
  """
  @spec update_config(t(), keyword()) :: t()
  def update_config(%__MODULE__{config: config} = adapter, updates) when is_list(updates) do
    current_opts = [
      client: config.client,
      cache_tools: config.cache_tools,
      timeout: config.timeout,
      async: config.async,
      fallback_client: config.fallback_client,
      before_fallback: config.before_fallback,
      tool_filter: config.tool_filter,
      context: config.context
    ]

    merged_opts = Keyword.merge(current_opts, updates)
    new_config = Config.new!(merged_opts)

    %{adapter | config: new_config}
  end

  @doc """
  Waits for the associated server for a client to be ready.

  If a client is started with start_link/1 the server initialization
  is asynchronous, so calling functions such as Adapter.discover_tools/2 or
  Adapter.to_functions/2 immediately after start link will produce a
  'Server capabilities not set' error.

  In this case, calling wait_for_server_ready/1 before calls to the Adapter
  ensures the server has time to initialize.

  ## Parameters

    * `client_pid` - The process ID for a Hermes client.
    * `timeout` - Maximum time to wait in milliseconds (default: 5000)

  ## Returns

    * `:ok` - Server is ready
    * `{:error, :initialization_timeout}` - Server didn't initialize within timeout
    * `{:error, :invalid_client}` - The provided PID is not a valid Hermes client

  ## Examples

      {:ok, client_pid} =
          MCPClient.start_link(
            client_info: ...,
            capabilities: ...,
            protocol_version: ...,
            transport: ...
          )

      case Adapter.wait_for_server_ready(client_pid) do
        :ok ->
          adapter = Adapter.new(client: client_pid)
          functions = Adapter.to_functions(adapter)
        {:error, reason} ->
          {:error, reason}
      end

  """
  @spec wait_for_server_ready(pid(), timeout :: non_neg_integer()) ::
          :ok | {:error, :initialization_timeout | :invalid_client}
  def wait_for_server_ready(client_pid, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_loop(client_pid, deadline)
  end

  defp wait_loop(client_pid, deadline) do
    # Get the Base client PID from the supervisor's children
    case get_base_client_pid(client_pid) do
      {:ok, base_pid} ->
        time = System.monotonic_time(:millisecond)

        case :sys.get_state(base_pid) do
          %{server_info: nil} when time < deadline ->
            Process.sleep(50)
            wait_loop(client_pid, deadline)

          %{server_info: nil} ->
            {:error, :initialization_timeout}

          _state ->
            :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper function to extract the Base client PID from the supervisor
  defp get_base_client_pid(supervisor_pid) do
    # Use a timeout to avoid blocking indefinitely on non-supervisor processes
    task =
      Task.async(fn ->
        try do
          children = Supervisor.which_children(supervisor_pid)

          case Enum.find(children, fn {id, _pid, _type, _modules} ->
                 id == Hermes.Client.Base
               end) do
            {_id, base_pid, _type, _modules} when is_pid(base_pid) ->
              {:ok, base_pid}

            nil ->
              {:error, :invalid_client}
          end
        catch
          :exit, _ ->
            {:error, :invalid_client}
        end
      end)

    case Task.yield(task, 100) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :invalid_client}
    end
  end
end
