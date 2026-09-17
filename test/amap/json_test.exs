defmodule Amap.JSONTest do
  use ExUnit.Case, async: false

  describe "with the default library" do
    test "defaults to the built-in JSON module" do
      assert Amap.JSON.json_library() == JSON
    end

    test "decodes" do
      assert Amap.JSON.decode(~s({"a":1})) == {:ok, %{"a" => 1}}
    end

    test "returns an error tuple rather than raising on malformed input" do
      assert {:error, _} = Amap.JSON.decode("{not json")
    end

    test "encodes" do
      assert Amap.JSON.encode!(%{"a" => 1}) == ~s({"a":1})
    end
  end

  describe "with a configured library" do
    setup do
      Application.put_env(:amap, :json_library, Amap.StubJSON)
      on_exit(fn -> Application.delete_env(:amap, :json_library) end)
    end

    test "routes both directions through the configured module" do
      assert Amap.JSON.json_library() == Amap.StubJSON
      assert Amap.JSON.decode("{}") == {:error, :stub}
      assert Amap.JSON.encode!(%{}) == "stubbed"
    end
  end
end
