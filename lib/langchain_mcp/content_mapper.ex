defmodule LangChain.MCP.ContentMapper do
  @moduledoc """
  Maps MCP content arrays to LangChain ContentPart structures.

  MCP tool responses contain a `content` array with multi-modal content items.
  This module converts them to LangChain's ContentPart format for use in messages
  and tool results.

  ## MCP Content Types

  MCP supports these content types:
  - `text` - Plain text content
  - `image` - Base64 encoded image data with mimeType
  - `resource` - Reference to a resource (file, URL, etc.)

  ## LangChain ContentPart Types

  These are mapped to:
  - `:text` - Text content
  - `:image` - Base64 image with media type
  - `:file` - File data (for resources)
  - `:unsupported` - For unknown types

  ## Examples

      # Text content
      mcp_content = [%{"type" => "text", "text" => "Hello world"}]
      parts = ContentMapper.to_content_parts(mcp_content)
      # => [%ContentPart{type: :text, content: "Hello world"}]

      # Image content
      mcp_content = [
        %{"type" => "image", "data" => "base64data...", "mimeType" => "image/png"}
      ]
      parts = ContentMapper.to_content_parts(mcp_content)
      # => [%ContentPart{type: :image, content: "base64data...", options: [media: "image/png"]}]

      # Mixed content
      mcp_content = [
        %{"type" => "text", "text" => "See this image:"},
        %{"type" => "image", "data" => "...", "mimeType" => "image/jpeg"}
      ]
      parts = ContentMapper.to_content_parts(mcp_content)
      # => [%ContentPart{type: :text, ...}, %ContentPart{type: :image, ...}]
  """

  alias LangChain.Message.ContentPart
  require Logger

  @doc """
  Converts an MCP content array to a list of ContentPart structs.

  ## Parameters

    * `mcp_content` - List of MCP content items (maps)

  ## Returns

    * List of `ContentPart.t()` structs

  ## Examples

      iex> mcp_content = [%{"type" => "text", "text" => "Result"}]
      iex> [part] = ContentMapper.to_content_parts(mcp_content)
      iex> part.type
      :text
      iex> part.content
      "Result"
  """
  @spec to_content_parts(list(map())) :: [ContentPart.t()]
  def to_content_parts(mcp_content) when is_list(mcp_content) do
    mcp_content
    |> Enum.map(&convert_content_item/1)
    |> Enum.reject(&is_nil/1)
  end

  def to_content_parts(_), do: []

  @doc """
  Extracts just the text content from an MCP content array.

  Useful when you only care about text responses and want to ignore other content types.

  ## Parameters

    * `mcp_content` - List of MCP content items

  ## Returns

    * String of concatenated text content, or `nil` if no text found

  ## Examples

      iex> mcp_content = [
      ...>   %{"type" => "text", "text" => "Hello "},
      ...>   %{"type" => "text", "text" => "world"},
      ...>   %{"type" => "image", "data" => "..."}
      ...> ]
      iex> ContentMapper.extract_text(mcp_content)
      "Hello world"
  """
  @spec extract_text(list(map())) :: String.t() | nil
  def extract_text(mcp_content) when is_list(mcp_content) do
    text_parts =
      mcp_content
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map(& &1["text"])
      |> Enum.reject(&is_nil/1)

    case text_parts do
      [] -> nil
      parts -> Enum.join(parts, "")
    end
  end

  def extract_text(_), do: nil

  # Convert individual content items
  defp convert_content_item(%{"type" => "text", "text" => text}) when is_binary(text) do
    case ContentPart.new(%{type: :text, content: text}) do
      {:ok, part} -> part
      {:error, _} -> nil
    end
  end

  # Text type with missing text field - invalid
  defp convert_content_item(%{"type" => "text"}) do
    Logger.warning("Text content missing 'text' field")
    nil
  end

  defp convert_content_item(%{"type" => "image"} = item) do
    data = item["data"]
    mime_type = item["mimeType"]

    if data && mime_type do
      options = [media: parse_mime_type(mime_type)]

      case ContentPart.new(%{type: :image, content: data, options: options}) do
        {:ok, part} -> part
        {:error, _} -> nil
      end
    else
      Logger.warning("Image content missing data or mimeType: #{inspect(item)}")
      nil
    end
  end

  defp convert_content_item(%{"type" => "resource"} = item) do
    # Resources can be files or other types
    # Try to map to file type if we have data
    uri = item["uri"]
    text = item["text"]
    mime_type = item["mimeType"]

    cond do
      text && is_binary(text) -> create_text_part(text)
      uri && is_binary(uri) -> create_file_url_part(uri, mime_type)
      true -> create_unsupported_part(item, "resource")
    end
  end

  defp convert_content_item(%{"type" => unknown_type} = item) do
    Logger.warning("Unknown MCP content type: #{unknown_type}")

    case ContentPart.new(%{
           type: :unsupported,
           content: inspect(item),
           options: [mcp_type: unknown_type]
         }) do
      {:ok, part} -> part
      {:error, _} -> nil
    end
  end

  defp convert_content_item(item) do
    Logger.warning("Invalid MCP content item: #{inspect(item)}")
    nil
  end

  defp create_text_part(text) do
    case ContentPart.new(%{type: :text, content: text}) do
      {:ok, part} -> part
      {:error, _} -> nil
    end
  end

  defp create_file_url_part(uri, mime_type) do
    options = if mime_type, do: [media: mime_type], else: []

    case ContentPart.new(%{type: :file_url, content: uri, options: options}) do
      {:ok, part} -> part
      {:error, _} -> nil
    end
  end

  defp create_unsupported_part(item, mcp_type) do
    Logger.debug("Resource content type not fully supported: #{inspect(item)}")

    case ContentPart.new(%{
           type: :unsupported,
           content: inspect(item),
           options: [mcp_type: mcp_type]
         }) do
      {:ok, part} -> part
      {:error, _} -> nil
    end
  end

  # Parse mime type into media format
  # Convert full mime types to shorthand when possible
  defp parse_mime_type("image/jpeg"), do: :jpg
  defp parse_mime_type("image/jpg"), do: :jpg
  defp parse_mime_type("image/png"), do: :png
  defp parse_mime_type("image/webp"), do: "image/webp"
  defp parse_mime_type("image/gif"), do: "image/gif"
  # Pass through other types as-is
  defp parse_mime_type(mime_type) when is_binary(mime_type), do: mime_type
  defp parse_mime_type(_), do: nil

  @doc """
  Checks if MCP content contains any text.

  ## Examples

      iex> mcp_content = [%{"type" => "text", "text" => "Hello"}]
      iex> ContentMapper.has_text?(mcp_content)
      true

      iex> mcp_content = [%{"type" => "image", "data" => "..."}]
      iex> ContentMapper.has_text?(mcp_content)
      false
  """
  @spec has_text?(list(map())) :: boolean()
  def has_text?(mcp_content) when is_list(mcp_content) do
    Enum.any?(mcp_content, &(&1["type"] == "text" && is_binary(&1["text"])))
  end

  def has_text?(_), do: false

  @doc """
  Checks if MCP content contains any images.

  ## Examples

      iex> mcp_content = [%{"type" => "image", "data" => "..."}]
      iex> ContentMapper.has_images?(mcp_content)
      true
  """
  @spec has_images?(list(map())) :: boolean()
  def has_images?(mcp_content) when is_list(mcp_content) do
    Enum.any?(mcp_content, &(&1["type"] == "image"))
  end

  def has_images?(_), do: false

  @doc """
  Converts LangChain ContentParts back to MCP content format.

  This is useful for testing or when you need to send content back to an MCP server.

  ## Parameters

    * `content_parts` - List of ContentPart structs

  ## Returns

    * List of MCP content maps
  """
  @spec from_content_parts([ContentPart.t()]) :: [map()]
  def from_content_parts(content_parts) when is_list(content_parts) do
    content_parts
    |> Enum.map(&convert_content_part_to_mcp/1)
    |> Enum.reject(&is_nil/1)
  end

  def from_content_parts(_), do: []

  defp convert_content_part_to_mcp(%ContentPart{type: :text, content: content})
       when is_binary(content) do
    %{"type" => "text", "text" => content}
  end

  defp convert_content_part_to_mcp(%ContentPart{type: :image, content: data, options: opts}) do
    mime_type = extract_mime_type(opts)

    %{
      "type" => "image",
      "data" => data,
      "mimeType" => mime_type || "image/png"
    }
  end

  defp convert_content_part_to_mcp(%ContentPart{type: :file_url, content: uri, options: opts}) do
    mime_type = extract_mime_type(opts)

    resource = %{"type" => "resource", "uri" => uri}

    if mime_type do
      Map.put(resource, "mimeType", mime_type)
    else
      resource
    end
  end

  defp convert_content_part_to_mcp(%ContentPart{type: :unsupported, options: opts}) do
    # Try to reconstruct original if mcp_type was preserved
    case Keyword.get(opts, :mcp_type) do
      nil -> nil
      mcp_type -> %{"type" => mcp_type}
    end
  end

  defp convert_content_part_to_mcp(_part) do
    # Skip unsupported conversions
    nil
  end

  defp extract_mime_type(opts) do
    case Keyword.get(opts, :media) do
      :jpg -> "image/jpeg"
      :png -> "image/png"
      mime when is_binary(mime) -> mime
      _ -> nil
    end
  end
end
