defmodule AvroEx.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  test "encoding of large integer as a union of int and long" do
    schema = ["int", "long"]
    data = -3_376_656_585_598_455_353

    json = Jason.encode!(schema)
    {:ok, schema} = AvroEx.decode_schema(json)
    {:ok, encoded} = AvroEx.encode(schema, data)

    assert {:ok, ^data} = AvroEx.decode(schema, encoded)
  end

  property "encode -> decode always returns back the initial data for the same schema" do
    check all schema <- schema(),
              data <- valid_data(schema),
              initial_size: 10 do
      json = Jason.encode!(schema)
      {:ok, schema} = AvroEx.decode_schema(json)
      {:ok, encoded} = AvroEx.encode(schema, data)
      assert {:ok, ^data} = AvroEx.decode(schema, encoded)
    end
  end

  def schema do
    sized(fn size -> schema_gen(size) end)
  end

  defp schema_gen(0), do: primitive()

  defp schema_gen(size) do
    frequency([
      {4, primitive()},
      {1, complex(size)}
    ])
  end

  defp primitive do
    member_of([
      "null",
      "boolean",
      "int",
      "long",
      "float",
      "double",
      "bytes",
      "string"
    ])
  end

  defp complex(size) do
    one_of([
      array(size),
      map(size),
      union(size)
    ])
  end

  defp array(size) do
    gen all schema <- resize(schema(), div(size, 2)) do
      %{
        type: "array",
        items: schema
      }
    end
  end

  defp map(size) do
    gen all schema <- resize(schema(), div(size, 2)) do
      %{
        type: "map",
        values: schema
      }
    end
  end

  defp union(size) do
    schema()
    |> resize(div(size, 4))
    |> filter(fn schema -> not is_list(schema) end)
    |> uniq_list_of(
      min_length: 1,
      max_length: 8,
      uniq_fun: fn
        %{type: _type, name: name} -> name
        %{type: type} -> type
        value -> value
      end
    )
  end

  defp valid_data("null"), do: constant(nil)
  defp valid_data("boolean"), do: boolean()
  defp valid_data("int"), do: integer(-2_147_483_648..2_147_483_647)
  defp valid_data("long"), do: integer(-9_223_372_036_854_775_808..9_223_372_036_854_775_807)

  defp valid_data("float") do
    gen all num <- float() do
      bin = <<num::float-size(32)>>
      <<float::float-size(32)>> = bin
      float
    end
  end

  defp valid_data("double"), do: float()
  defp valid_data("bytes"), do: binary(min_length: 1)
  defp valid_data("string"), do: string(:printable)
  defp valid_data(%{type: "array", items: schema}), do: list_of(valid_data(schema))
  defp valid_data(%{type: "map", values: schema}), do: map_of(valid_data("string"), valid_data(schema))

  defp valid_data(union) when is_list(union) do
    union
    |> member_of()
    |> bind(&valid_data/1)
  end
end
