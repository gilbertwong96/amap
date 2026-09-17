defmodule AmapTest do
  # Not async: these tests mutate global application config, which is shared
  # state. Running them concurrently with another module that reads
  # `config :amap` would make the assertions racy.
  use ExUnit.Case, async: false

  describe "new/1" do
    test "takes the key from options" do
      client = Amap.new(key: "abc")

      assert client.key == "abc"
      assert client.private_key == nil
      assert client.limiter == nil
      assert client.timeout == 5_000
      assert client.pool == Amap.Finch
      assert client.retry == []
    end

    test "defaults both family base URLs" do
      client = Amap.new(key: "abc")

      assert client.base_urls.restapi == "https://restapi.amap.com"
      assert client.base_urls.tsapi == "https://tsapi.amap.com"
    end

    test "falls back to application config" do
      Application.put_env(:amap, :key, "from-config")

      on_exit(fn -> Application.delete_env(:amap, :key) end)

      assert Amap.new().key == "from-config"
    end

    test "falls back to the top-level key when the client config sets a nil key" do
      Application.put_env(:amap, :client, key: nil, timeout: 1_000)
      Application.put_env(:amap, :key, "from-config")

      on_exit(fn ->
        Application.delete_env(:amap, :client)
        Application.delete_env(:amap, :key)
      end)

      assert Amap.new().key == "from-config"
    end

    test "explicit options win over application config" do
      Application.put_env(:amap, :key, "from-config")

      on_exit(fn -> Application.delete_env(:amap, :key) end)

      assert Amap.new(key: "explicit").key == "explicit"
    end

    test "raises when no key is available" do
      assert_raise ArgumentError, ~r/:key is required/, fn -> Amap.new() end
    end

    test "rejects unknown options" do
      assert_raise ArgumentError, ~r/unknown option/, fn ->
        Amap.new(key: "abc", keey: "typo")
      end
    end
  end
end
