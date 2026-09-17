defmodule Amap.ResponseTest do
  use ExUnit.Case, async: true

  describe "decode/1" do
    test "decodes a JSON body" do
      assert Amap.Response.decode(~s({"a":1})) == {:ok, %{"a" => 1}}
    end

    test "returns the raw body when the JSON is malformed" do
      assert Amap.Response.decode("<html/>") == {:error, "<html/>"}
    end
  end

  describe "normalize/3 for the Web service family" do
    test "strips the envelope and keeps the payload" do
      body = %{
        "status" => "1",
        "info" => "OK",
        "infocode" => "10000",
        "count" => "1",
        "geocodes" => [%{"formatted_address" => "北京市"}]
      }

      assert {:ok, payload} = Amap.Response.normalize(:restapi, body, 200)
      assert payload == %{"count" => "1", "geocodes" => [%{"formatted_address" => "北京市"}]}
      refute Map.has_key?(payload, "status")
      refute Map.has_key?(payload, "infocode")
    end

    test "turns a failed status into an error" do
      body = %{"status" => "0", "info" => "INVALID_USER_KEY", "infocode" => "10001"}

      assert {:error, error} = Amap.Response.normalize(:restapi, body, 200)
      assert error.reason == :invalid_key
      assert error.family == :restapi
      assert error.http_status == 200
    end
  end

  describe "normalize/3 for the Falcon family" do
    test "unwraps data" do
      body = %{"errcode" => 0, "errmsg" => "OK", "data" => %{"sid" => 1}}

      assert {:ok, %{"sid" => 1}} = Amap.Response.normalize(:tsapi, body, 200)
    end

    test "accepts a string errcode of zero" do
      body = %{"errcode" => "0", "errmsg" => "OK", "data" => %{"sid" => 1}}

      assert {:ok, %{"sid" => 1}} = Amap.Response.normalize(:tsapi, body, 200)
    end

    test "returns nil data for write-only endpoints" do
      assert {:ok, nil} =
               Amap.Response.normalize(:tsapi, %{"errcode" => 0, "errmsg" => "OK"}, 200)
    end

    test "turns a non-zero errcode into an error" do
      body = %{"errcode" => 20051, "errmsg" => "TERMINAL_NOT_FOUND"}

      assert {:error, error} = Amap.Response.normalize(:tsapi, body, 200)
      assert error.reason == :terminal_not_found
    end

    test "treats partial success as success, not as a failure" do
      body = %{"errcode" => 20100, "errmsg" => "PARTIAL_SUCCESS", "data" => %{"succeeded" => 1}}

      assert {:ok, %{"succeeded" => 1}} = Amap.Response.normalize(:tsapi, body, 200)
    end

    test "treats nothing success as a failure" do
      body = %{"errcode" => 20101, "errmsg" => "NOTHING_SUCCESS"}

      assert {:error, error} = Amap.Response.normalize(:tsapi, body, 200)
      assert error.reason == :nothing_success
    end
  end

  describe "normalize/3 for unrecognized bodies" do
    test "rejects a body matching neither envelope" do
      assert {:error, error} = Amap.Response.normalize(:tsapi, %{"weird" => true}, 200)
      assert error.reason == :unexpected_response
    end

    test "rejects a non-map payload" do
      assert {:error, error} = Amap.Response.normalize(:restapi, ["a"], 200)
      assert error.reason == :unexpected_response
    end

    test "degrades on a non-numeric errcode instead of raising" do
      assert {:error, error} = Amap.Response.normalize(:tsapi, %{"errcode" => "abc"}, 200)
      assert error.reason == :unexpected_response
      assert error.code == nil
    end
  end

  describe "partial?/2" do
    test "is true only for 20100" do
      assert Amap.Response.partial?(:tsapi, %{"errcode" => 20100})
      refute Amap.Response.partial?(:tsapi, %{"errcode" => 0})
      refute Amap.Response.partial?(:restapi, %{"status" => "1"})
    end

    test "is false for a non-numeric errcode" do
      refute Amap.Response.partial?(:tsapi, %{"errcode" => "abc"})
    end
  end
end
