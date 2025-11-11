defmodule LangChain.MCP.SchemaConverter do
  @moduledoc """
  Converts MCP tool input schemas (JSON Schema format) to LangChain FunctionParam structures.

  MCP tools define their parameters using JSON Schema format. This module handles
  the conversion to LangChain's `FunctionParam` format, supporting:

  - Simple types (string, integer, number, boolean)
  - Arrays (with item types)
  - Objects (with nested properties)
  - Enums
  - Required fields
  - Descriptions

  ## Examples

      # Simple parameter
      schema = %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "Search query"}
        },
        "required" => ["query"]
      }

      params = SchemaConverter.to_parameters(schema)
      # => [%FunctionParam{name: "query", type: :string, description: "Search query", required: true}]

      # Complex nested object
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

      params = SchemaConverter.to_parameters(schema)
  """

  alias LangChain.FunctionParam
  require Logger

  @type json_schema :: map()

  @doc """
  Converts a JSON Schema object to a list of LangChain FunctionParam structs.

  The schema should be an object with `type: "object"`, `properties`, and optionally `required`.

  ## Parameters

    * `schema` - JSON Schema map (typically from MCP tool's inputSchema)

  ## Returns

    * List of `FunctionParam` structs

  ## Examples

      iex> schema = %{
      ...>   "type" => "object",
      ...>   "properties" => %{
      ...>     "name" => %{"type" => "string"},
      ...>     "count" => %{"type" => "integer"}
      ...>   },
      ...>   "required" => ["name"]
      ...> }
      iex> params = SchemaConverter.to_parameters(schema)
      iex> length(params)
      2
      iex> Enum.find(params, & &1.name == "name").required
      true
  """
  @spec to_parameters(json_schema()) :: [FunctionParam.t()]
  def to_parameters(%{"type" => "object"} = schema) do
    properties = schema["properties"] || %{}
    required_fields = schema["required"] || []

    properties
    |> Enum.map(fn {name, prop_schema} ->
      convert_property(name, prop_schema, name in required_fields)
    end)
    |> Enum.reject(&is_nil/1)
  end

  def to_parameters(_schema) do
    Logger.warning("Schema is not an object type, returning empty parameters")
    []
  end

  @doc """
  Converts a single property from JSON Schema to FunctionParam.

  ## Parameters

    * `name` - Property name
    * `prop_schema` - Property schema map
    * `required` - Whether this property is required

  ## Returns

    * `FunctionParam.t()` or `nil` if conversion fails
  """
  @spec convert_property(String.t(), map(), boolean()) :: FunctionParam.t() | nil
  def convert_property(name, prop_schema, required \\ false)

  def convert_property(name, %{"type" => type} = prop_schema, required) do
    base_attrs = %{
      name: name,
      description: prop_schema["description"],
      required: required
    }

    type_specific_attrs = convert_type(type, prop_schema)

    case FunctionParam.new(Map.merge(base_attrs, type_specific_attrs)) do
      {:ok, param} ->
        param

      {:error, changeset} ->
        Logger.error("Failed to create FunctionParam for '#{name}': #{inspect(changeset.errors)}")

        nil
    end
  end

  def convert_property(name, prop_schema, _required) do
    Logger.warning("Property '#{name}' has no type: #{inspect(prop_schema)}")
    nil
  end

  # Convert type-specific attributes
  defp convert_type("string", prop_schema) do
    attrs = %{type: :string}

    # Handle enum if present
    case prop_schema["enum"] do
      enum when is_list(enum) and length(enum) > 0 ->
        Map.put(attrs, :enum, enum)

      _ ->
        attrs
    end
  end

  defp convert_type("integer", prop_schema) do
    attrs = %{type: :integer}

    case prop_schema["enum"] do
      enum when is_list(enum) and length(enum) > 0 ->
        Map.put(attrs, :enum, enum)

      _ ->
        attrs
    end
  end

  defp convert_type("number", _prop_schema) do
    %{type: :number}
  end

  defp convert_type("boolean", _prop_schema) do
    %{type: :boolean}
  end

  defp convert_type("array", prop_schema) do
    attrs = %{type: :array}

    # Handle items schema
    case prop_schema["items"] do
      %{"type" => item_type} = items_schema when item_type == "object" ->
        # Array of objects - need to convert nested properties
        nested_props = convert_nested_object_properties(items_schema)

        attrs
        |> Map.put(:item_type, "object")
        |> Map.put(:object_properties, nested_props)

      %{"type" => item_type} ->
        # Array of simple types
        Map.put(attrs, :item_type, item_type)

      _ ->
        # No items specified, allow mixed array
        attrs
    end
  end

  defp convert_type("object", prop_schema) do
    nested_props = convert_nested_object_properties(prop_schema)

    %{
      type: :object,
      object_properties: nested_props
    }
  end

  defp convert_type(unknown_type, _prop_schema) do
    Logger.warning("Unknown JSON Schema type: #{unknown_type}, defaulting to string")
    %{type: :string}
  end

  # Convert nested object properties to FunctionParam list
  defp convert_nested_object_properties(object_schema) do
    properties = object_schema["properties"] || %{}
    required_fields = object_schema["required"] || []

    properties
    |> Enum.map(fn {name, nested_schema} ->
      convert_property(name, nested_schema, name in required_fields)
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Converts LangChain FunctionParam list back to JSON Schema format.

  This is useful for debugging or when you need to reconstruct the original schema.

  ## Parameters

    * `params` - List of FunctionParam structs

  ## Returns

    * JSON Schema map

  ## Examples

      iex> params = [
      ...>   FunctionParam.new!(%{name: "query", type: :string, required: true})
      ...> ]
      iex> schema = SchemaConverter.from_parameters(params)
      iex> schema["type"]
      "object"
      iex> schema["required"]
      ["query"]
  """
  @spec from_parameters([FunctionParam.t()]) :: json_schema()
  def from_parameters(params) when is_list(params) do
    properties =
      params
      |> Enum.map(&param_to_property/1)
      |> Enum.into(%{})

    required =
      params
      |> Enum.filter(& &1.required)
      |> Enum.map(& &1.name)

    schema = %{
      "type" => "object",
      "properties" => properties
    }

    if length(required) > 0 do
      Map.put(schema, "required", required)
    else
      schema
    end
  end

  defp param_to_property(%FunctionParam{} = param) do
    prop = %{
      "type" => type_to_string(param.type)
    }

    prop =
      if param.description do
        Map.put(prop, "description", param.description)
      else
        prop
      end

    prop =
      if length(param.enum) > 0 do
        Map.put(prop, "enum", param.enum)
      else
        prop
      end

    prop =
      case param.type do
        :array ->
          add_array_items(prop, param)

        :object ->
          add_object_properties(prop, param)

        _ ->
          prop
      end

    {param.name, prop}
  end

  defp type_to_string(:string), do: "string"
  defp type_to_string(:integer), do: "integer"
  defp type_to_string(:number), do: "number"
  defp type_to_string(:boolean), do: "boolean"
  defp type_to_string(:array), do: "array"
  defp type_to_string(:object), do: "object"

  defp add_array_items(prop, %FunctionParam{item_type: nil}), do: prop

  defp add_array_items(prop, %FunctionParam{item_type: "object", object_properties: obj_props}) do
    items_schema =
      %{
        "type" => "object",
        "properties" =>
          obj_props
          |> Enum.map(&param_to_property/1)
          |> Enum.into(%{})
      }

    required =
      obj_props
      |> Enum.filter(& &1.required)
      |> Enum.map(& &1.name)

    items_schema =
      if length(required) > 0 do
        Map.put(items_schema, "required", required)
      else
        items_schema
      end

    Map.put(prop, "items", items_schema)
  end

  defp add_array_items(prop, %FunctionParam{item_type: item_type}) do
    Map.put(prop, "items", %{"type" => item_type})
  end

  defp add_object_properties(prop, %FunctionParam{object_properties: obj_props}) do
    properties =
      obj_props
      |> Enum.map(&param_to_property/1)
      |> Enum.into(%{})

    required =
      obj_props
      |> Enum.filter(& &1.required)
      |> Enum.map(& &1.name)

    prop = Map.put(prop, "properties", properties)

    if length(required) > 0 do
      Map.put(prop, "required", required)
    else
      prop
    end
  end
end
