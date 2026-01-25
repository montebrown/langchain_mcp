defmodule LangChain.MCP.Config do
  @moduledoc """
  Configuration structure for MCP adapter.

  Holds settings for MCP client integration including caching, timeouts,
  fallback behavior, and tool filtering.

  ## Fields

    * `:client` - The Anubis.Client module to use for MCP operations (required)
    * `:cache_tools` - Whether to cache discovered tools (default: true)
    * `:timeout` - Timeout for tool calls in milliseconds (default: 30_000)
    * `:async` - Whether to mark tools as async (default: false)
    * `:fallback_client` - Optional fallback client module if primary fails
    * `:before_fallback` - Optional function called before fallback, receives (config, tool_name, args)
    * `:tool_filter` - Optional function to filter tools, receives tool map, returns boolean
    * `:context` - Optional context map passed to tool execution callbacks

  ## Examples

      # Basic configuration
      config = Config.new!(client: MyApp.MCPClient)

      # With fallback
      config = Config.new!(
        client: MyApp.PrimaryMCP,
        fallback_client: MyApp.BackupMCP,
        before_fallback: fn _config, tool_name, _args ->
          Logger.warning("Falling back for tool: \#{tool_name}")
          :continue
        end
      )

      # With tool filtering
      config = Config.new!(
        client: MyApp.MCPClient,
        tool_filter: fn tool ->
          tool["name"] not in ["dangerous_tool", "admin_only"]
        end
      )
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:client, :any, virtual: true)
    field(:cache_tools, :boolean, default: true)
    field(:timeout, :integer, default: 30_000)
    field(:async, :boolean, default: false)
    field(:fallback_client, :any, virtual: true)
    field(:before_fallback, :any, virtual: true)
    field(:tool_filter, :any, virtual: true)
    field(:context, :map, virtual: true, default: %{})
  end

  @typedoc "A client reference that can be a module, PID, or GenServer-compatible name"
  @type client_ref :: module() | pid() | GenServer.server()

  @type t :: %__MODULE__{
          client: client_ref(),
          cache_tools: boolean(),
          timeout: pos_integer(),
          async: boolean(),
          fallback_client: client_ref() | nil,
          before_fallback: function() | nil,
          tool_filter: function() | nil,
          context: map()
        }

  @doc """
  Creates a new Config struct with validation.

  ## Options

    * `:client` - Required. The Anubis.Client module, PID, or via tuple
    * `:cache_tools` - Boolean, default true
    * `:timeout` - Positive integer in ms, default 30_000
    * `:async` - Boolean, default false
    * `:fallback_client` - Optional module, PID, or via tuple
    * `:before_fallback` - Optional 3-arity function
    * `:tool_filter` - Optional 1-arity function
    * `:context` - Optional map

  ## Client Types

  The `:client` and `:fallback_client` options accept:
    * Module name (atom) - e.g., `MyApp.MCPClient`
    * PID - e.g., a dynamically started client
    * Via tuple - e.g., `{:via, Registry, {MyRegistry, "key"}}`
    * Global tuple - e.g., `{:global, :my_client}`

  ## Examples

      iex> Config.new!(client: MyApp.MCPClient)
      %Config{client: MyApp.MCPClient, cache_tools: true, ...}

      iex> Config.new!(client: MyApp.MCPClient, timeout: 60_000, async: true)
      %Config{client: MyApp.MCPClient, timeout: 60_000, async: true, ...}
  """
  @spec new!(keyword()) :: t() | no_return()
  def new!(attrs) when is_list(attrs) do
    case new(attrs) do
      {:ok, config} -> config
      {:error, changeset} -> raise ArgumentError, "Invalid config: #{inspect(changeset.errors)}"
    end
  end

  @doc """
  Creates a new Config struct with validation, returning ok/error tuple.

  See `new!/1` for options.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(attrs) when is_list(attrs) do
    %__MODULE__{}
    |> changeset(Map.new(attrs))
    |> apply_action(:insert)
  end

  @doc false
  def changeset(config, attrs) do
    config
    |> cast(attrs, [:cache_tools, :timeout, :async, :context])
    |> validate_required([:cache_tools, :timeout, :async])
    |> validate_number(:timeout, greater_than: 0)
    |> put_virtual_fields(attrs)
    |> validate_client()
    |> validate_fallback_client()
    |> validate_callbacks()
  end

  defp put_virtual_fields(changeset, attrs) do
    changeset
    |> put_change_if_present(:client, attrs[:client])
    |> put_change_if_present(:fallback_client, attrs[:fallback_client])
    |> put_change_if_present(:before_fallback, attrs[:before_fallback])
    |> put_change_if_present(:tool_filter, attrs[:tool_filter])
  end

  defp put_change_if_present(changeset, _key, nil), do: changeset

  defp put_change_if_present(changeset, key, value) do
    put_change(changeset, key, value)
  end

  defp validate_client(changeset) do
    case get_field(changeset, :client) do
      nil ->
        add_error(changeset, :client, "is required")

      client when is_atom(client) ->
        # Check if module exists
        if Code.ensure_loaded?(client) do
          changeset
        else
          add_error(changeset, :client, "module does not exist")
        end

      client when is_pid(client) ->
        # Check if PID is alive
        if Process.alive?(client) do
          changeset
        else
          add_error(changeset, :client, "PID is not alive")
        end

      {:via, module, _term} when is_atom(module) ->
        # Accept via tuples with structure validation only
        changeset

      {:global, _name} ->
        # Accept global tuples
        changeset

      _ ->
        add_error(changeset, :client, "must be a module name (atom)")
    end
  end

  defp validate_fallback_client(changeset) do
    case get_field(changeset, :fallback_client) do
      nil ->
        # Fallback client is optional
        changeset

      client when is_atom(client) ->
        # Check if module exists
        if Code.ensure_loaded?(client) do
          changeset
        else
          add_error(changeset, :fallback_client, "module does not exist")
        end

      client when is_pid(client) ->
        # Check if PID is alive
        if Process.alive?(client) do
          changeset
        else
          add_error(changeset, :fallback_client, "PID is not alive")
        end

      {:via, module, _term} when is_atom(module) ->
        # Accept via tuples with structure validation only
        changeset

      {:global, _name} ->
        # Accept global tuples
        changeset

      _ ->
        add_error(changeset, :fallback_client, "must be a module name (atom)")
    end
  end

  defp validate_callbacks(changeset) do
    changeset
    |> validate_function(:before_fallback, 3)
    |> validate_function(:tool_filter, 1)
  end

  defp validate_function(changeset, field, arity) do
    case get_field(changeset, field) do
      nil ->
        changeset

      fun when is_function(fun, arity) ->
        changeset

      fun when is_function(fun) ->
        add_error(changeset, field, "must be a function with arity #{arity}")

      _ ->
        add_error(changeset, field, "must be a function")
    end
  end

  @doc """
  Returns true if a fallback client is configured.

  ## Examples

      iex> config = Config.new!(client: MyApp.MCP)
      iex> Config.has_fallback?(config)
      false

      iex> config = Config.new!(client: MyApp.MCP, fallback_client: MyApp.Backup)
      iex> Config.has_fallback?(config)
      true
  """
  @spec has_fallback?(t()) :: boolean()
  def has_fallback?(%__MODULE__{fallback_client: nil}), do: false
  def has_fallback?(%__MODULE__{fallback_client: _}), do: true

  @doc """
  Applies the tool filter function if configured.

  Returns true if no filter is configured or if the filter returns true.

  ## Examples

      iex> config = Config.new!(client: MyApp.MCP)
      iex> Config.filter_tool?(config, %{"name" => "any_tool"})
      true

      iex> config = Config.new!(client: MyApp.MCP, tool_filter: fn t -> t["name"] == "allowed" end)
      iex> Config.filter_tool?(config, %{"name" => "allowed"})
      true
      iex> Config.filter_tool?(config, %{"name" => "blocked"})
      false
  """
  @spec filter_tool?(t(), map()) :: boolean()
  def filter_tool?(%__MODULE__{tool_filter: nil}, _tool), do: true

  def filter_tool?(%__MODULE__{tool_filter: filter}, tool) when is_function(filter, 1) do
    filter.(tool)
  end

  @doc """
  Calls the before_fallback callback if configured.

  Returns `:continue` to proceed with fallback, `:skip` to skip it.

  ## Examples

      iex> config = Config.new!(client: MyApp.MCP)
      iex> Config.before_fallback(config, "tool_name", %{})
      :continue

      iex> config = Config.new!(
      ...>   client: MyApp.MCP,
      ...>   before_fallback: fn _, _, _ -> :skip end
      ...> )
      iex> Config.before_fallback(config, "tool_name", %{})
      :skip
  """
  @spec before_fallback(t(), String.t(), map()) :: :continue | :skip
  def before_fallback(%__MODULE__{before_fallback: nil}, _tool_name, _args), do: :continue

  def before_fallback(%__MODULE__{before_fallback: callback} = config, tool_name, args)
      when is_function(callback, 3) do
    case callback.(config, tool_name, args) do
      :skip -> :skip
      :continue -> :continue
      _ -> :continue
    end
  end
end
