defmodule LangChain.MCP.SchemaConverterTest do
  use ExUnit.Case, async: true

  alias LangChain.FunctionParam
  alias LangChain.MCP.SchemaConverter

  describe "to_parameters/1" do
    test "converts simple string parameter" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "User name"}
        },
        "required" => ["name"]
      }

      [param] = SchemaConverter.to_parameters(schema)

      assert param.name == "name"
      assert param.type == :string
      assert param.description == "User name"
      assert param.required == true
    end

    test "converts multiple parameters with mixed types" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string"},
          "limit" => %{"type" => "integer"},
          "enabled" => %{"type" => "boolean"}
        },
        "required" => ["query"]
      }

      params = SchemaConverter.to_parameters(schema)

      assert length(params) == 3

      query_param = Enum.find(params, &(&1.name == "query"))
      assert query_param.type == :string
      assert query_param.required == true

      limit_param = Enum.find(params, &(&1.name == "limit"))
      assert limit_param.type == :integer
      assert limit_param.required == false
    end

    test "converts enum parameter" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "color" => %{
            "type" => "string",
            "enum" => ["red", "green", "blue"]
          }
        }
      }

      [param] = SchemaConverter.to_parameters(schema)

      assert param.enum == ["red", "green", "blue"]
    end

    test "converts array parameter with item type" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "tags" => %{
            "type" => "array",
            "items" => %{"type" => "string"}
          }
        }
      }

      [param] = SchemaConverter.to_parameters(schema)

      assert param.type == :array
      assert param.item_type == "string"
    end

    test "converts nested object parameter" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "user" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string"},
              "age" => %{"type" => "integer"}
            },
            "required" => ["name"]
          }
        }
      }

      [param] = SchemaConverter.to_parameters(schema)

      assert param.type == :object
      assert length(param.object_properties) == 2

      name_prop = Enum.find(param.object_properties, &(&1.name == "name"))
      assert name_prop.required == true
    end

    test "handles empty schema" do
      schema = %{"type" => "object", "properties" => %{}}

      params = SchemaConverter.to_parameters(schema)

      assert params == []
    end

    test "handles non-object schema" do
      schema = %{"type" => "string"}

      params = SchemaConverter.to_parameters(schema)

      assert params == []
    end
  end

  describe "from_parameters/1" do
    test "converts parameters back to JSON Schema" do
      params = [
        FunctionParam.new!(%{name: "query", type: :string, required: true}),
        FunctionParam.new!(%{name: "limit", type: :integer})
      ]

      schema = SchemaConverter.from_parameters(params)

      assert schema["type"] == "object"
      assert schema["properties"]["query"]["type"] == "string"
      assert schema["properties"]["limit"]["type"] == "integer"
      assert schema["required"] == ["query"]
    end

    test "round-trip conversion preserves structure" do
      original_schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "Name"},
          "count" => %{"type" => "integer"}
        },
        "required" => ["name"]
      }

      params = SchemaConverter.to_parameters(original_schema)
      converted_schema = SchemaConverter.from_parameters(params)

      assert converted_schema["type"] == original_schema["type"]
      assert converted_schema["required"] == original_schema["required"]
      assert map_size(converted_schema["properties"]) == 2
    end
  end
end
