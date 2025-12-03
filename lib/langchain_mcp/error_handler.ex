defmodule LangChain.MCP.ErrorHandler do
  @moduledoc """
  Handles error translation from MCP to LangChain format.

  MCP has three types of errors:
  1. **Protocol Errors** - JSON-RPC communication errors (returned as `{:error, %Error{}}`)
  2. **Transport Errors** - Connection/network failures (returned as `{:error, %Error{}}`)
  3. **Domain Errors** - Application-level errors (returned as `{:ok, %Response{is_error: true}}`)

  This module normalizes all error types into LangChain's error format: `{:error, reason}`

  ## Examples

      # Protocol error
      {:error, error} = call_mcp_tool(...)
      {:error, reason} = ErrorHandler.handle_error(error)
      # reason: "MCP protocol error: invalid_request"

      # Domain error in response
      {:ok, response} = call_mcp_tool(...)
      if response.is_error do
        {:error, reason} = ErrorHandler.handle_response_error(response)
        # reason: "Tool execution failed: ..."
      end

      # Check if error should trigger fallback
      ErrorHandler.should_retry?(error)
      # => true (for network errors, timeouts, etc.)
      # => false (for invalid parameters, etc.)
  """

  require Logger

  @doc """
  Handles MCP protocol/transport errors and converts to LangChain format.

  ## Parameters

    * `error` - Anubis.MCP.Error struct or any error term

  ## Returns

    * `{:error, String.t()}` - Human-readable error message

  ## Examples

      iex> error = %Anubis.MCP.Error{code: -32600, reason: :invalid_request}
      iex> ErrorHandler.handle_error(error)
      {:error, "MCP protocol error (invalid_request): Invalid request format"}
  """
  @spec handle_error(term()) :: {:error, String.t()}
  def handle_error(%{__struct__: struct_name, code: code, reason: reason} = error)
      when struct_name in [Anubis.MCP.Error, Anubis.Client.Error] do
    message = format_error_message(reason, code, error)
    Logger.warning("MCP error: #{message}")
    {:error, message}
  end

  def handle_error(error) when is_binary(error) do
    {:error, "MCP error: #{error}"}
  end

  def handle_error(error) when is_atom(error) do
    {:error, "MCP error: #{error}"}
  end

  def handle_error(error) do
    {:error, "MCP error: #{inspect(error)}"}
  end

  @doc """
  Handles MCP domain errors from responses (is_error: true).

  ## Parameters

    * `response` - Anubis.MCP.Response struct with is_error: true

  ## Returns

    * `{:error, String.t()}` - Error message from response

  ## Examples

      iex> response = %Anubis.MCP.Response{
      ...>   is_error: true,
      ...>   result: %{"isError" => true, "content" => [%{"type" => "text", "text" => "Not found"}]}
      ...> }
      iex> ErrorHandler.handle_response_error(response)
      {:error, "Tool execution failed: Not found"}
  """
  @spec handle_response_error(map()) :: {:error, String.t()}
  def handle_response_error(%{is_error: true, result: result}) do
    message = extract_error_message(result)
    Logger.warning("MCP tool execution error: #{message}")
    {:error, message}
  end

  def handle_response_error(response) do
    Logger.warning("Unexpected response format: #{inspect(response)}")
    {:error, "Unexpected response format"}
  end

  @doc """
  Determines if an error should trigger a fallback retry.

  Returns true for transient errors (network, timeout, server errors)
  Returns false for permanent errors (invalid params, auth failures)

  ## Parameters

    * `error` - Error term (Anubis.MCP.Error or other)

  ## Returns

    * `boolean()` - true if should retry with fallback

  ## Examples

      iex> error = %Anubis.MCP.Error{reason: :request_timeout}
      iex> ErrorHandler.should_retry?(error)
      true

      iex> error = %Anubis.MCP.Error{reason: :invalid_params}
      iex> ErrorHandler.should_retry?(error)
      false
  """
  @spec should_retry?(term()) :: boolean()
  def should_retry?(%{__struct__: struct_name, reason: reason})
      when struct_name in [Anubis.MCP.Error, Anubis.Client.Error] do
    transient_error?(reason)
  end

  def should_retry?(_error), do: false

  defp transient_error?(reason)
       when reason in [
              :request_timeout,
              :send_failure,
              :connection_refused,
              :internal_error,
              :server_error
            ],
       do: true

  defp transient_error?(_reason), do: false

  # Format error messages based on reason codes
  defp format_error_message(:parse_error, _code, _error) do
    "MCP protocol error (parse_error): Invalid JSON in request or response"
  end

  defp format_error_message(:invalid_request, _code, _error) do
    "MCP protocol error (invalid_request): Invalid request format"
  end

  defp format_error_message(:method_not_found, _code, error) do
    method = Map.get(error, :data, %{}) |> Map.get("method", "unknown")
    "MCP protocol error (method_not_found): Method '#{method}' not found"
  end

  defp format_error_message(:invalid_params, _code, _error) do
    "MCP protocol error (invalid_params): Invalid parameters provided"
  end

  defp format_error_message(:internal_error, _code, _error) do
    "MCP protocol error (internal_error): Server internal error"
  end

  defp format_error_message(:request_timeout, _code, _error) do
    "MCP transport error (request_timeout): Request timed out"
  end

  defp format_error_message(:send_failure, _code, _error) do
    "MCP transport error (send_failure): Failed to send message"
  end

  defp format_error_message(:connection_refused, _code, _error) do
    "MCP transport error (connection_refused): Could not connect to server"
  end

  defp format_error_message(:request_cancelled, _code, _error) do
    "MCP transport error (request_cancelled): Request was cancelled"
  end

  defp format_error_message(reason, code, error) when is_atom(reason) do
    message = Map.get(error, :message, "No message provided")
    "MCP error (#{reason}, code: #{code}): #{message}"
  end

  defp format_error_message(_reason, code, error) do
    message = Map.get(error, :message, inspect(error))
    "MCP error (code: #{code}): #{message}"
  end

  # Extract error message from MCP domain error result
  defp extract_error_message(%{"content" => content}) when is_list(content) do
    # Try to find text content with error message
    text_content =
      content
      |> Enum.find(fn item -> item["type"] == "text" end)
      |> case do
        %{"text" => text} -> text
        _ -> nil
      end

    if text_content do
      "Tool execution failed: #{text_content}"
    else
      "Tool execution failed: #{inspect(content)}"
    end
  end

  defp extract_error_message(result) when is_map(result) do
    # Try to find any descriptive fields
    cond do
      Map.has_key?(result, "error") ->
        "Tool execution failed: #{inspect(result["error"])}"

      Map.has_key?(result, "message") ->
        "Tool execution failed: #{result["message"]}"

      true ->
        "Tool execution failed: #{inspect(result)}"
    end
  end

  defp extract_error_message(result) do
    "Tool execution failed: #{inspect(result)}"
  end

  @doc """
  Wraps an error with additional context about the tool call.

  ## Parameters

    * `error` - Original error
    * `tool_name` - Name of the tool that failed
    * `args` - Arguments passed to the tool

  ## Returns

    * `{:error, String.t()}` - Error with added context

  ## Examples

      iex> ErrorHandler.wrap_tool_error({:error, "timeout"}, "search", %{"query" => "test"})
      {:error, "Tool 'search' failed: timeout"}
  """
  @spec wrap_tool_error({:error, term()}, String.t(), map()) :: {:error, String.t()}
  def wrap_tool_error({:error, reason}, tool_name, _args) when is_binary(reason) do
    {:error, "Tool '#{tool_name}' failed: #{reason}"}
  end

  def wrap_tool_error({:error, reason}, tool_name, args) do
    {:error, "Tool '#{tool_name}' with args #{inspect(args)} failed: #{inspect(reason)}"}
  end

  def wrap_tool_error(error, tool_name, args) do
    {:error, "Tool '#{tool_name}' with args #{inspect(args)} failed: #{inspect(error)}"}
  end
end
