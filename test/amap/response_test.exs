defmodule Amap.ResponseTest do
  use ExUnit.Case, async: true

  alias Amap.Response

  describe "decode/1" do
    test "decodes a JSON body" do
      assert Response.decode(~s({"a":1})) == {:ok, %{"a" => 1}}
    end

    test "returns the raw body when the JSON is malformed" do
      assert Response.decode("<html/>") == {:error, "<html/>"}
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

      assert {:ok, payload} = Response.normalize(:restapi, body, 200)
      assert payload == %{"count" => "1", "geocodes" => [%{"formatted_address" => "北京市"}]}
      refute Map.has_key?(payload, "status")
      refute Map.has_key?(payload, "infocode")
    end

    test "reads an empty array as no value, at any depth" do
      # 当返回值不存在时，则以数组类型返回 — the rule this SDK promises callers, so the
      # four empty arrays `/v3/ip` sends for an address it cannot place reach a
      # struct as nil.
      body = %{
        "status" => "1",
        "info" => "OK",
        "infocode" => "10000",
        "province" => [],
        "regeocode" => %{"roads" => [], "addressComponent" => %{"city" => []}}
      }

      assert {:ok, payload} = Response.normalize(:restapi, body, 200)
      assert payload["province"] == nil
      assert payload["regeocode"]["roads"] == nil
      assert payload["regeocode"]["addressComponent"]["city"] == nil
    end

    test "keeps a non-empty list, and normalises what is inside it" do
      body = %{
        "status" => "1",
        "info" => "OK",
        "infocode" => "10000",
        "geocodes" => [%{"address" => "北京市", "level" => []}]
      }

      assert {:ok, payload} = Response.normalize(:restapi, body, 200)
      assert payload["geocodes"] == [%{"address" => "北京市", "level" => nil}]
    end

    test "turns a failed status into an error" do
      body = %{"status" => "0", "info" => "INVALID_USER_KEY", "infocode" => "10001"}

      assert {:error, error} = Response.normalize(:restapi, body, 200)
      assert error.reason == :invalid_key
      assert error.family == :restapi
      assert error.http_status == 200
    end
  end

  describe "normalize/3 for the Falcon family" do
    test "unwraps data" do
      body = %{"errcode" => 0, "errmsg" => "OK", "data" => %{"sid" => 1}}

      assert {:ok, %{"sid" => 1}} = Response.normalize(:tsapi, body, 200)
    end

    # The live API's success code, copied verbatim from a real Service.add
    # response. Treating only 0 as success made this look like a failure while
    # Amap had already created the service.
    test "treats 10000 as success, which is what the live API sends" do
      body = %{
        "errcode" => 10_000,
        "errmsg" => "OK",
        "data" => %{"name" => "sdk_it_2722", "sid" => 1_078_149}
      }

      assert {:ok, %{"name" => "sdk_it_2722", "sid" => 1_078_149}} =
               Response.normalize(:tsapi, body, 200)
    end

    test "accepts 10000 as a string too" do
      body = %{"errcode" => "10000", "errmsg" => "OK", "data" => %{"sid" => 1}}

      assert {:ok, %{"sid" => 1}} = Response.normalize(:tsapi, body, 200)
    end

    test "reads an empty-array data as no data at all" do
      # Amap writes "no value" as an empty array: 当返回值不存在时，则以数组类型返回.
      body = %{"errcode" => 10_000, "errmsg" => "OK", "data" => []}

      assert {:ok, nil} = Response.normalize(:tsapi, body, 200)
    end

    test "unwraps an object the service sent inside an array" do
      # The analysis endpoints answered `data: [%{…}]` live while their own tables
      # describe an object, so a single-element array is read as a wrapper.
      body = %{"errcode" => 10_000, "errmsg" => "OK", "data" => [%{"distance" => 425}]}

      assert {:ok, %{"distance" => 425}} = Response.normalize(:tsapi, body, 200)
    end

    test "accepts a string errcode of zero" do
      body = %{"errcode" => "0", "errmsg" => "OK", "data" => %{"sid" => 1}}

      assert {:ok, %{"sid" => 1}} = Response.normalize(:tsapi, body, 200)
    end

    test "returns nil data for write-only endpoints" do
      assert {:ok, nil} =
               Response.normalize(:tsapi, %{"errcode" => 0, "errmsg" => "OK"}, 200)
    end

    test "turns a non-zero errcode into an error" do
      body = %{"errcode" => 20051, "errmsg" => "TERMINAL_NOT_FOUND"}

      assert {:error, error} = Response.normalize(:tsapi, body, 200)
      assert error.reason == :terminal_not_found
    end

    test "treats partial success as success, not as a failure" do
      body = %{"errcode" => 20100, "errmsg" => "PARTIAL_SUCCESS", "data" => %{"succeeded" => 1}}

      assert {:ok, %{"succeeded" => 1}} = Response.normalize(:tsapi, body, 200)
    end

    test "treats nothing success as a failure" do
      body = %{"errcode" => 20101, "errmsg" => "NOTHING_SUCCESS"}

      assert {:error, error} = Response.normalize(:tsapi, body, 200)
      assert error.reason == :nothing_success
    end
  end

  describe "normalize/3 for unrecognized bodies" do
    test "rejects a body matching neither envelope" do
      assert {:error, error} = Response.normalize(:tsapi, %{"weird" => true}, 200)
      assert error.reason == :unexpected_response
    end

    test "rejects a non-map payload" do
      assert {:error, error} = Response.normalize(:restapi, ["a"], 200)
      assert error.reason == :unexpected_response
    end

    test "degrades on a non-numeric errcode instead of raising" do
      assert {:error, error} = Response.normalize(:tsapi, %{"errcode" => "abc"}, 200)
      assert error.reason == :unexpected_response
      assert error.code == nil
    end
  end

  describe "partial?/2" do
    test "is true only for 20100" do
      assert Response.partial?(:tsapi, %{"errcode" => 20100})
      refute Response.partial?(:tsapi, %{"errcode" => 0})
      refute Response.partial?(:restapi, %{"status" => "1"})
    end

    test "is false for a non-numeric errcode" do
      refute Response.partial?(:tsapi, %{"errcode" => "abc"})
    end
  end
end
