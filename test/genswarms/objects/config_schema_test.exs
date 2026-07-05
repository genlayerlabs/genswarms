defmodule Genswarms.Objects.ConfigSchemaTest do
  use ExUnit.Case, async: true

  alias Genswarms.Objects.ConfigSchema

  @schema %{
    "type" => "object",
    "properties" => %{
      "templates" => %{"type" => "object", "x-mutable" => true},
      "max_per_run" => %{"type" => "integer", "x-mutable" => true},
      "phone_id" => %{"type" => "string"},
      "access_token_env" => %{"type" => "string", "x-secret" => true}
    }
  }

  test "mutable keys pass and are atomized (nested keys too)" do
    patch = %{"templates" => %{"greeting" => "pt_PT"}, "max_per_run" => 5}

    assert {:ok, atom_patch} = ConfigSchema.validate_with_schema(@schema, patch)
    assert atom_patch == %{templates: %{greeting: "pt_PT"}, max_per_run: 5}
  end

  test "non-mutable keys are rejected, even schema'd ones" do
    assert {:error, {:immutable_keys, ["phone_id"]}} =
             ConfigSchema.validate_with_schema(@schema, %{"phone_id" => "1"})

    # secrets are never mutable via the API
    assert {:error, {:immutable_keys, ["access_token_env"]}} =
             ConfigSchema.validate_with_schema(@schema, %{"access_token_env" => "X"})
  end

  test "keys absent from the schema are rejected" do
    assert {:error, {:immutable_keys, ["mystery"]}} =
             ConfigSchema.validate_with_schema(@schema, %{"mystery" => 1})
  end

  test "no schema -> every patch rejected (fail-closed)" do
    assert {:error, :no_config_schema} =
             ConfigSchema.validate_with_schema(nil, %{"templates" => %{}})
  end

  test "host-escape keys are rejected unconditionally, before any schema logic" do
    hostile = Map.put(@schema, "properties", %{"extra_ro_binds" => %{"x-mutable" => true}})

    assert {:error, {:forbidden_keys, ["extra_ro_binds"]}} =
             ConfigSchema.validate_with_schema(hostile, %{"extra_ro_binds" => [["/", "/host"]]})
  end

  test "oversized patches are rejected (atom-table backstop)" do
    big = Map.new(1..201, fn i -> {"k#{i}", i} end)
    assert {:error, :patch_too_large} = ConfigSchema.validate_with_schema(@schema, big)
  end

  test "non-object patch is rejected" do
    assert {:error, :patch_must_be_object} = ConfigSchema.validate_with_schema(@schema, "nope")
    assert {:error, :patch_must_be_object} = ConfigSchema.validate_with_schema(@schema, [1, 2])
  end

  test "schema_for is nil for unloaded/invalid handlers (fail-closed)" do
    assert ConfigSchema.schema_for(:not_a_module) == nil
    assert ConfigSchema.schema_for(nil) == nil
  end
end
