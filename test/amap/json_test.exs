defmodule Amap.JSONTest do
  use ExUnit.Case, async: false

  # `alias Amap.JSON` would be `JSON`, but the standard library owns that name and
  # the first test below asserts against it directly, so the alias is renamed.
  alias Amap.JSON, as: JSONModule

  describe "with the default library" do
    test "defaults to the built-in JSON module" do
      assert JSONModule.json_library() == JSON
    end

    test "decodes" do
      assert JSONModule.decode(~s({"a":1})) == {:ok, %{"a" => 1}}
    end

    test "returns an error tuple rather than raising on malformed input" do
      assert {:error, _} = JSONModule.decode("{not json")
    end

    test "encodes" do
      assert JSONModule.encode!(%{"a" => 1}) == ~s({"a":1})
    end
  end

  describe "with a configured library" do
    setup do
      Application.put_env(:amap, :json_library, Amap.StubJSON)
      on_exit(fn -> Application.delete_env(:amap, :json_library) end)
    end

    test "routes both directions through the configured module" do
      assert JSONModule.json_library() == Amap.StubJSON
      assert JSONModule.decode("{}") == {:error, :stub}
      assert JSONModule.encode!(%{}) == "stubbed"
    end
  end
end
