defmodule Amap.SearchTest do
  use ExUnit.Case, async: true

  alias Amap.Search
  alias Amap.TestServer

  describe "types/2" do
    test "joins a category list with |, names or six-digit codes alike" do
      assert Search.types(["住宿服务", "餐饮服务"], ":types") == "住宿服务|餐饮服务"
      assert Search.types(["050000", "070000"], ":types") == "050000|070000"
      assert Search.types(["050000"], ":types") == "050000"
    end

    test "treats nil as absent" do
      assert Search.types(nil, ":types") == nil
    end

    test "refuses a bare string, which would be split character by character" do
      assert_raise ArgumentError, ~r/:types must be a non-empty list/, fn ->
        Search.types("050000", ":types")
      end
    end

    test "refuses an empty list and a list holding something that is not a name" do
      assert_raise ArgumentError, ~r/:types must be a non-empty list/, fn ->
        Search.types([], ":types")
      end

      assert_raise ArgumentError, ~r/:types must be a list of non-empty strings/, fn ->
        Search.types(["050000", ""], ":types")
      end

      assert_raise ArgumentError, ~r/:types must be a list of non-empty strings/, fn ->
        Search.types([:"050000"], ":types")
      end
    end

    test "names the field it was called for" do
      assert_raise ArgumentError, ~r/:type must be a non-empty list/, fn ->
        Search.types("poi", ":type")
      end
    end
  end

  describe "keyword_or_types/2" do
    test "returns whichever of the pair was given" do
      assert Search.keyword_or_types(keywords: "北京大学") ==
               [keywords: "北京大学", types: nil]

      assert Search.keyword_or_types(types: ["141201"]) == [keywords: nil, types: "141201"]
    end

    test "returns both when both were given" do
      assert Search.keyword_or_types(keywords: "KFC", types: ["050301"]) ==
               [keywords: "KFC", types: "050301"]
    end

    test "raises for neither, which is the page's 二选一必填" do
      assert_raise ArgumentError, ~r/one of :keywords or :types is required/, fn ->
        Search.keyword_or_types([])
      end

      assert_raise ArgumentError, ~r/:keywords must be a non-empty string/, fn ->
        Search.keyword_or_types(keywords: "")
      end
    end

    test "holds the v5 80-character keyword rule when it is asked to" do
      eighty = String.duplicate("北", 80)

      assert Search.keyword_or_types([keywords: eighty], 80) == [keywords: eighty, types: nil]

      assert_raise ArgumentError, ~r/:keywords must be at most 80 characters, got: 81/, fn ->
        Search.keyword_or_types([keywords: eighty <> "大"], 80)
      end
    end

    test "leaves the length unlimited when no rule was passed" do
      long = String.duplicate("a", 200)
      assert Search.keyword_or_types(keywords: long) == [keywords: long, types: nil]
    end
  end

  describe "polygon/1" do
    test "joins coordinate pairs with |, longitude first, as the Web-service pages want" do
      assert Search.polygon([{116.460988, 40.006919}, {116.48231, 40.007381}]) ==
               "116.460988,40.006919|116.48231,40.007381"
    end

    test "formats small coordinates without scientific notation" do
      assert Search.polygon([{0.00001, 0.00002}, {1.0, 2.0}]) == "0.00001,0.00002|1.0,2.0"
    end

    test "refuses anything that is not a non-empty list of pairs" do
      assert_raise ArgumentError,
                   ~r/:polygon must be a non-empty list of \{lon, lat\} pairs/,
                   fn ->
                     Search.polygon([])
                   end

      assert_raise ArgumentError,
                   ~r/:polygon must be a non-empty list of \{lon, lat\} pairs/,
                   fn ->
                     Search.polygon("116.46,40.00|116.48,40.00")
                   end

      assert_raise ArgumentError, ~r/:polygon must be a \{lon, lat\} pair of numbers/, fn ->
        Search.polygon([{116.46, 40.0}, {"116.48", 40.0}])
      end
    end
  end

  describe "pois/2" do
    test "reads the pois.poi wrapper and maps each entry" do
      payload = %{"pois" => %{"poi" => [%{"id" => "1"}, %{"id" => "2"}]}}

      assert Search.pois(payload, & &1["id"]) == ["1", "2"]
    end

    test "answers a list the wrapper wrote as an array with nothing in it" do
      assert Search.pois(%{"pois" => %{"poi" => nil}}, & &1) == []
      assert Search.pois(%{"count" => "0"}, & &1) == []
    end

    test "accepts a bare list too, and drops entries that are not objects" do
      assert Search.pois(%{"pois" => [%{"id" => "1"}, "junk"]}, & &1["id"]) == ["1"]
      assert Search.pois(%{"pois" => "junk"}, & &1) == []
    end
  end

  describe "fetch/4" do
    setup do
      server = TestServer.start!()

      client =
        Amap.new(
          key: "test-key",
          base_urls: %{
            restapi: "http://localhost:#{server.port}",
            tsapi: "http://localhost:#{server.port}"
          }
        )

      {:ok, server: server, client: client}
    end

    test "sends the parameters and hands the payload to the mapper", %{
      server: server,
      client: client
    } do
      parent = self()

      TestServer.expect_once(server, "GET", "/v5/place/text", fn req ->
        send(parent, {:query, URI.decode_query(req.query)})
        {200, ~s<{"status":"1","info":"OK","infocode":"10000","count":"1"}>}
      end)

      assert {:ok, "1"} =
               Search.fetch(client, "/v5/place/text", [keywords: "北京大学"], & &1["count"])

      assert_receive {:query, query}
      assert query["keywords"] == "北京大学"
      assert query["key"] == "test-key"
    end

    test "returns a refusal as an error rather than raising", %{server: server, client: client} do
      refusal = ~s<{"status":"0","info":"INVALID_USER_KEY","infocode":"10001"}>

      TestServer.expect_once(server, "GET", "/v3/place/text", fn _req -> {200, refusal} end)

      assert {:error, %Amap.Error{}} =
               Search.fetch(client, "/v3/place/text", [keywords: "北京大学"], & &1)
    end
  end
end
