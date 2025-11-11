defmodule LangChain.MCP.ContentMapperTest do
  use ExUnit.Case, async: true

  alias LangChain.MCP.ContentMapper
  alias LangChain.Message.ContentPart

  describe "to_content_parts/1" do
    test "converts text content" do
      mcp_content = [
        %{"type" => "text", "text" => "Hello world"}
      ]

      [part] = ContentMapper.to_content_parts(mcp_content)

      assert part.type == :text
      assert part.content == "Hello world"
    end

    test "converts multiple text items" do
      mcp_content = [
        %{"type" => "text", "text" => "First"},
        %{"type" => "text", "text" => "Second"}
      ]

      parts = ContentMapper.to_content_parts(mcp_content)

      assert length(parts) == 2
      assert Enum.at(parts, 0).content == "First"
      assert Enum.at(parts, 1).content == "Second"
    end

    test "converts image content" do
      mcp_content = [
        %{
          "type" => "image",
          "data" => "base64encodeddata",
          "mimeType" => "image/png"
        }
      ]

      [part] = ContentMapper.to_content_parts(mcp_content)

      assert part.type == :image
      assert part.content == "base64encodeddata"
      assert Keyword.get(part.options, :media) == :png
    end

    test "converts mixed content" do
      mcp_content = [
        %{"type" => "text", "text" => "See image:"},
        %{
          "type" => "image",
          "data" => "imagedata",
          "mimeType" => "image/jpeg"
        }
      ]

      parts = ContentMapper.to_content_parts(mcp_content)

      assert length(parts) == 2
      assert Enum.at(parts, 0).type == :text
      assert Enum.at(parts, 1).type == :image
    end

    test "handles empty content array" do
      parts = ContentMapper.to_content_parts([])

      assert parts == []
    end

    test "skips invalid content items" do
      mcp_content = [
        %{"type" => "text", "text" => "Valid"},
        # Missing text field
        %{"type" => "text"},
        # Missing type
        %{"invalid" => "item"}
      ]

      parts = ContentMapper.to_content_parts(mcp_content)

      IO.inspect(parts)

      assert length(parts) == 1
      assert hd(parts).content == "Valid"
    end
  end

  describe "extract_text/1" do
    test "extracts text from single text item" do
      mcp_content = [
        %{"type" => "text", "text" => "Hello"}
      ]

      text = ContentMapper.extract_text(mcp_content)

      assert text == "Hello"
    end

    test "concatenates multiple text items" do
      mcp_content = [
        %{"type" => "text", "text" => "Hello "},
        %{"type" => "text", "text" => "world"}
      ]

      text = ContentMapper.extract_text(mcp_content)

      assert text == "Hello world"
    end

    test "ignores non-text items" do
      mcp_content = [
        %{"type" => "text", "text" => "Text only"},
        %{"type" => "image", "data" => "..."}
      ]

      text = ContentMapper.extract_text(mcp_content)

      assert text == "Text only"
    end

    test "returns nil when no text content" do
      mcp_content = [
        %{"type" => "image", "data" => "..."}
      ]

      text = ContentMapper.extract_text(mcp_content)

      assert text == nil
    end
  end

  describe "has_text?/1 and has_images?/1" do
    test "detects text content" do
      mcp_content = [
        %{"type" => "text", "text" => "Hello"}
      ]

      assert ContentMapper.has_text?(mcp_content) == true
      assert ContentMapper.has_images?(mcp_content) == false
    end

    test "detects image content" do
      mcp_content = [
        %{"type" => "image", "data" => "...", "mimeType" => "image/png"}
      ]

      assert ContentMapper.has_text?(mcp_content) == false
      assert ContentMapper.has_images?(mcp_content) == true
    end

    test "detects mixed content" do
      mcp_content = [
        %{"type" => "text", "text" => "Hello"},
        %{"type" => "image", "data" => "...", "mimeType" => "image/png"}
      ]

      assert ContentMapper.has_text?(mcp_content) == true
      assert ContentMapper.has_images?(mcp_content) == true
    end
  end

  describe "from_content_parts/1" do
    test "converts text ContentPart to MCP format" do
      parts = [
        ContentPart.new!(%{type: :text, content: "Hello"})
      ]

      [mcp_item] = ContentMapper.from_content_parts(parts)

      assert mcp_item["type"] == "text"
      assert mcp_item["text"] == "Hello"
    end

    test "converts image ContentPart to MCP format" do
      parts = [
        ContentPart.new!(%{
          type: :image,
          content: "base64data",
          options: [media: :png]
        })
      ]

      [mcp_item] = ContentMapper.from_content_parts(parts)

      assert mcp_item["type"] == "image"
      assert mcp_item["data"] == "base64data"
      assert mcp_item["mimeType"] == "image/png"
    end
  end
end
