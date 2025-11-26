defmodule LangChain.MCP.ToolExecutor do
  @moduledoc """
  Executes MCP tool calls and handles responses.

  This module bridges MCP tool execution with LangChain's function calling system.
  It handles:
  - Calling MCP tools via Anubis.Client
  - Converting results to LangChain format (text, ContentParts, or ToolResult)
  - Error handling with fallback support
  - Timeout and async execution options

  ## Examples

      # Simple execution
      config = Config.new!(client: MyApp.MCPClient)
      {:ok, result} = ToolExecutor.execute(config, "search", %{"query" => "elixir"})

      # With fallback
      config = Config.new!(
        client: MyApp.PrimaryMCP,
        fallback_client: MyApp.BackupMCP
      )
      {:ok, result} = ToolExecutor.execute(config, "search", %{"query" => "elixir"})

      # Result formats:
      # - String: "Search results: ..."
      # - ContentParts: [%ContentPart{type: :text, ...}, %ContentPart{type: :image, ...}]
      # - ToolResult: %ToolResult{content: ..., is_error: false}
  """

  alias LangChain.MCP.{Config, ContentMapper, ErrorHandler}
  alias LangChain.Message.{ContentPart, ToolResult}
  require Logger

  @type execution_result ::
          String.t() | [ContentPart.t()] | ToolResult.t()

  @doc """
  Executes an MCP tool and returns the result in LangChain format.

  ## Parameters

    * `config` - MCP Config struct
    * `tool_name` - Name of the tool to execute
    * `args` - Map of arguments to pass to the tool
    * `context` - Optional context map (merged with config context)

  ## Returns

    * `{:ok, result}` - Success with string, ContentParts, or ToolResult
    * `{:error, reason}` - Failure with error message

  ## Examples

      iex> config = Config.new!(client: MyApp.MCPClient)
      iex> {:ok, result} = ToolExecutor.execute(config, "echo", %{"text" => "hello"})
      iex> is_binary(result)
      true
  """
  @spec execute(Config.t(), String.t(), map(), map()) ::
          {:ok, execution_result()} | {:error, String.t()}
  def execute(%Config{} = config, tool_name, args, context \\ %{})
      # when is_binary(tool_name) and is_map(args) do
      when is_binary(tool_name) do
    merged_context = Map.merge(config.context, context)

    # Try primary client
    case execute_on_client(config.client, tool_name, args, config.timeout, merged_context) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} = error ->
        original_error = extract_original_error(reason)

        # Check if we should try fallback
        if Config.has_fallback?(config) &&
             should_use_fallback?(config, original_error, tool_name, args) do
          Logger.info("Attempting fallback client for tool '#{tool_name}'")

          execute_on_client(
            config.fallback_client,
            tool_name,
            args || %{},
            config.timeout,
            merged_context
          )
        else
          error
        end
    end
  end

  @doc """
  Executes a tool on a specific client without fallback logic.

  Used internally by `execute/4` and useful for testing.

  ## Parameters

    * `client` - Anubis.Client module
    * `tool_name` - Tool name
    * `args` - Arguments map
    * `timeout` - Timeout in milliseconds (default: 30_000)
    * `context` - Context map (default: %{})

  ## Returns

    * `{:ok, result}` - Success
    * `{:error, reason}` - Failure
  """
  @spec execute_on_client(module(), String.t(), map(), pos_integer(), map()) ::
          {:ok, execution_result()} | {:error, String.t()}
  def execute_on_client(client, tool_name, args, timeout \\ 30_000, context \\ %{}) do
    opts = build_call_opts(timeout)

    # Call the MCP tool via Anubis.Client
    case apply(client, :call_tool, [tool_name, args, opts]) do
      {:ok, response} ->
        handle_response(response, tool_name, context)

      {:error, error} ->
        ErrorHandler.handle_error(error)
        |> ErrorHandler.wrap_tool_error(tool_name, args)
    end
  rescue
    error ->
      Logger.error("Exception during MCP tool execution: #{inspect(error)}")
      {:error, "Tool execution exception: #{Exception.message(error)}"}
  end

  # Handle successful MCP response
  defp handle_response(%{is_error: false, result: result}, _tool_name, context) do
    convert_result_to_langchain(result, context)
  end

  # Handle domain error in response
  defp handle_response(%{is_error: true} = response, _tool_name, _context) do
    ErrorHandler.handle_response_error(response)
  end

  defp handle_response(response, tool_name, _context) do
    Logger.warning("Unexpected response format from tool '#{tool_name}': #{inspect(response)}")
    {:error, "Unexpected response format"}
  end

  # Convert MCP result to LangChain format
  defp convert_result_to_langchain(%{"content" => content}, context) when is_list(content) do
    cond do
      # If single text item, return as string
      single_text?(content) ->
        text = ContentMapper.extract_text(content)
        wrap_result(text, context)

      # If multiple items or non-text, return as ContentParts
      true ->
        parts = ContentMapper.to_content_parts(content)
        wrap_result(parts, context)
    end
  end

  defp convert_result_to_langchain(result, context) do
    # Fallback: convert result to string
    wrap_result(inspect(result), context)
  end

  # Check if content is a single text item
  defp single_text?([%{"type" => "text", "text" => _text}]), do: true
  defp single_text?(_), do: false

  # Wrap result based on context requirements
  defp wrap_result(result, context) do
    # If context specifies return format, honor it
    case Map.get(context, :return_format) do
      :tool_result ->
        {:ok, build_tool_result(result)}

      :content_parts when is_binary(result) ->
        parts = [ContentPart.new!(%{type: :text, content: result})]
        {:ok, parts}

      :content_parts when is_list(result) ->
        {:ok, result}

      _ ->
        # Default: return as-is
        {:ok, result}
    end
  end

  defp build_tool_result(content) when is_binary(content) do
    ToolResult.new!(%{
      content: content,
      is_error: false
    })
  end

  defp build_tool_result(content) when is_list(content) do
    ToolResult.new!(%{
      content: content,
      is_error: false
    })
  end

  # Build call options for Anubis.Client
  defp build_call_opts(timeout) do
    [timeout: timeout]
  end

  # Determine if fallback should be used
  defp should_use_fallback?(config, error_reason, tool_name, args) do
    # Check if error is retryable
    retryable = ErrorHandler.should_retry?(error_reason)

    if retryable do
      # Call before_fallback callback if configured
      case Config.before_fallback(config, tool_name, args) do
        :continue -> true
        :skip -> false
      end
    else
      false
    end
  end

  # Extract original error struct from processed error string
  defp extract_original_error(error_message) when is_binary(error_message) do
    # Parse the message to get back to original Anubis.MCP.Error structure
    cond do
      String.contains?(error_message, "request_timeout") ->
        %Anubis.MCP.Error{code: -1, reason: :request_timeout}

      String.contains?(error_message, "internal_error") ->
        %Anubis.MCP.Error{code: -1, reason: :internal_error}

      true ->
        %Anubis.MCP.Error{code: -1, reason: :unknown}
    end
  end

  defp extract_original_error(error), do: error

  @doc """
  Validates that a tool exists on the MCP server before execution.

  This is optional but can provide better error messages.

  ## Parameters

    * `client` - Anubis.Client module
    * `tool_name` - Tool name to validate

  ## Returns

    * `:ok` - Tool exists
    * `{:error, reason}` - Tool not found or error listing tools

  ## Examples

      iex> ToolExecutor.validate_tool(MyApp.MCPClient, "search")
      :ok

      iex> ToolExecutor.validate_tool(MyApp.MCPClient, "nonexistent")
      {:error, "Tool 'nonexistent' not found on MCP server"}
  """
  @spec validate_tool(module(), String.t()) :: :ok | {:error, String.t()}
  def validate_tool(client, tool_name) do
    case apply(client, :list_tools, []) do
      {:ok, response} ->
        tools = response["result"]["tools"] || []
        tool_names = Enum.map(tools, & &1["name"])

        if tool_name in tool_names do
          :ok
        else
          {:error, "Tool '#{tool_name}' not found on MCP server. Available: #{inspect(tool_names)}"}
        end

      {:error, error} ->
        ErrorHandler.handle_error(error)
    end
  end

  @doc """
  Lists all available tools on an MCP server.

  ## Parameters

    * `client` - Anubis.Client module

  ## Returns

    * `{:ok, tool_list}` - List of tool maps
    * `{:error, reason}` - Error listing tools

  ## Examples

      iex> {:ok, tools} = ToolExecutor.list_tools(MyApp.MCPClient)
      iex> is_list(tools)
      true
  """
  @spec list_tools(module()) :: {:ok, [map()]} | {:error, String.t()}
  def list_tools(client) do
    list_tools_with_retry(client, 3, 50)
  end

  @spec list_tools_with_retry(module(), non_neg_integer(), non_neg_integer()) ::
          {:ok, [map()]} | {:error, String.t()}
  defp list_tools_with_retry(client, retries_left, delay_ms) when retries_left > 0 do
    case apply(client, :list_tools, []) do
      {:ok, response} ->
        tools = response.result["tools"] || []
        {:ok, tools}

      {:error, %{reason: :internal_error} = error} ->
        # Internal error with "Server capabilities not set" means
        # the client hasn't finished initialization yet - retry with backoff
        data = Map.get(error, :data, %{})
        data_message = Map.get(data, :message, "")

        if is_binary(data_message) and String.contains?(data_message, "Server capabilities not set") and
             retries_left > 1 do
          Process.sleep(delay_ms)
          list_tools_with_retry(client, retries_left - 1, delay_ms * 2)
        else
          ErrorHandler.handle_error(error)
        end

      {:error, error} ->
        ErrorHandler.handle_error(error)
    end
  end

  defp list_tools_with_retry(_client, 0, _delay_ms) do
    {:error, "Failed to list tools after retries"}
  end
end
