defmodule Amap.DistrictTest do
  use ExUnit.Case, async: true

  alias Amap.District
  alias Amap.District.Result
  alias Amap.District.Suggestion
  alias Amap.TestServer

  @beijing ~s({"status":"1","info":"OK","infocode":"10000",) <>
             ~s("suggestion":{"keywords":[],"cities":[]},"districts":[) <>
             ~s({"citycode":"010","adcode":"110000","name":"北京市",) <>
             ~s("level":"province","center":"116.407526,39.904030",) <>
             ~s("districts":[{"citycode":"010","adcode":"110101","name":"东城区",) <>
             ~s("level":"district","center":"116.418757,39.917544","districts":[]}]}]})

  @chaoyang ~s({"status":"1","info":"OK","infocode":"10000",) <>
              ~s("suggestion":{"keywords":[],"cities":[]},"districts":[) <>
              ~s({"adcode":"110105","name":"朝阳区","level":"district",) <>
              ~s("center":"116.486409,39.921489",) <>
              ~s("polyline":"116.4,39.9;116.5,39.95|116.6,40.0"}]})

  @nothing ~s({"status":"1","info":"OK","infocode":"10000",) <>
             ~s("suggestion":{"keywords":["北京"],"cities":["北京市"]},"districts":[]})

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

  test "sends the key alone when nothing was asked for", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/config/district", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @beijing}
    end)

    assert {:ok, %Result{}} = District.district(client)

    assert_receive {:query, query}
    assert Map.keys(query) == ["key"]
  end

  test "sends every parameter Amap documents", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/config/district", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @beijing}
    end)

    District.district(client,
      keywords: "北京",
      subdistrict: 2,
      page: 2,
      offset: 10,
      extensions: :all,
      filter: "110000"
    )

    assert_receive {:query, query}
    assert query["keywords"] == "北京"
    assert query["subdistrict"] == "2"
    assert query["page"] == "2"
    assert query["offset"] == "10"
    assert query["extensions"] == "all"
    assert query["filter"] == "110000"
  end

  test "rejects a value Amap does not document", %{client: client} do
    assert_raise ArgumentError, ~r/:subdistrict must be between 0 and 4, got: 5/, fn ->
      District.district(client, subdistrict: 5)
    end

    assert_raise ArgumentError, ~r/:page must be between 1 and 1000000, got: 0/, fn ->
      District.district(client, page: 0)
    end

    assert_raise ArgumentError, ~r/:offset must be between 1 and 20, got: 21/, fn ->
      District.district(client, offset: 21)
    end

    assert_raise ArgumentError, ~r/:extensions must be one of \[:base, :all\], got: :full/, fn ->
      District.district(client, extensions: :full)
    end

    assert_raise ArgumentError, ~r/:keywords must be a non-empty string/, fn ->
      District.district(client, keywords: "")
    end
  end

  test "maps a province and its children, one level deep", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/config/district", fn _req -> {200, @beijing} end)

    assert {:ok, result} = District.district(client, keywords: "北京")
    assert [%District{} = province] = result.items
    assert province.name == "北京市"
    assert province.adcode == "110000"
    assert province.citycode == "010"
    assert province.level == "province"
    assert province.center == {116.407526, 39.90403}

    assert [%District{} = child] = province.districts
    assert child.name == "东城区"
    assert child.level == "district"
    assert child.districts == []

    assert result.suggestion == %Suggestion{keywords: [], cities: []}
  end

  test "parses a boundary that arrives in two pieces", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/config/district", fn _req -> {200, @chaoyang} end)

    assert {:ok, %Result{items: [%District{} = chaoyang]}} =
             District.district(client, keywords: "朝阳区", extensions: :all)

    assert chaoyang.polyline == [
             [{116.4, 39.9}, {116.5, 39.95}],
             [{116.6, 40.0}]
           ]
  end

  test "carries Amap's suggestion when nothing matched", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/config/district", fn _req -> {200, @nothing} end)

    assert {:ok, result} = District.district(client, keywords: "北金")

    assert result.items == []
    assert result.suggestion == %Suggestion{keywords: ["北京"], cities: ["北京市"]}
  end

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    refusal = ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

    TestServer.expect_once(server, "GET", "/v3/config/district", fn _req -> {200, refusal} end)

    assert {:error, %Amap.Error{}} = District.district(client, keywords: "北京")
  end
end
