defmodule Amap.Direction.DistanceTest do
  use ExUnit.Case, async: true

  alias Amap.Direction
  alias Amap.Direction.Distance
  alias Amap.TestServer

  @measured ~s({"status":"1","info":"OK","infocode":"10000","count":"2",) <>
              ~s("results":[{"origin_id":"1","dest_id":"1","distance":"12345","duration":"1200"},) <>
              ~s({"origin_id":"2","dest_id":"1","distance":"6789","duration":"900",) <>
              ~s("info":"未知错误","code":"2"}]})

  @nested ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
            ~s("results":{"result":[{"origin_id":"1","dest_id":"1",) <>
            ~s("distance":"12345","duration":"1200"}]}})

  @none ~s({"status":"1","info":"OK","infocode":"10000","count":"0","results":[]})

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

  test "sends many origins pipe-separated, and one destination", %{server: server, client: client} do
    parent = self()
    expect_distance(server, @measured, parent)

    assert {:ok, [%Distance{}, %Distance{}]} =
             Direction.distance(
               client,
               [{116.481028, 39.989643}, {114.481028, 39.989643}],
               {114.465302, 40.004717}
             )

    assert_receive {:query, query}
    # `|` between pairs, as this endpoint takes them — not the `;` the response
    # side uses, which is what `Amap.Param.locations/1` would send.
    assert query["origins"] == "116.481028,39.989643|114.481028,39.989643"
    assert query["destination"] == "114.465302,40.004717"
    # The wire default is Amap's own `1`, so the parameter stays out unless asked.
    refute Map.has_key?(query, "type")
  end

  test "takes one hundred origins and refuses one hundred and one", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_distance(server, @measured, parent)

    origins = for i <- 1..100, do: {116.0 + i / 1000, 39.0}

    assert {:ok, [_ | _]} = Direction.distance(client, origins, {114.465302, 40.004717})
    assert_receive {:query, _query}

    assert_raise ArgumentError, ~r/:origins count/, fn ->
      Direction.distance(client, origins ++ [{117.0, 40.0}], {114.465302, 40.004717})
    end
  end

  test "refuses an empty origin list", %{client: client} do
    assert_raise ArgumentError, ~r/:origins/, fn ->
      Direction.distance(client, [], {114.465302, 40.004717})
    end
  end

  test "sends :type when given, and refuses what Amap does not document", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_distance(server, @measured, parent)

    assert {:ok, [_ | _]} =
             Direction.distance(
               client,
               [{116.481028, 39.989643}],
               {114.465302, 40.004717},
               type: 3
             )

    assert_receive {:query, query}
    assert query["type"] == "3"

    parent = self()
    expect_distance(server, @measured, parent)

    assert {:ok, [_ | _]} =
             Direction.distance(
               client,
               [{116.481028, 39.989643}],
               {114.465302, 40.004717},
               type: 0
             )

    assert_receive {:query, query}
    assert query["type"] == "0"

    for bad <- [2, 4, "1"] do
      assert_raise ArgumentError, ~r/:type/, fn ->
        Direction.distance(
          client,
          [{116.481028, 39.989643}],
          {114.465302, 40.004717},
          type: bad
        )
      end
    end
  end

  test "keeps the sequence numbers as strings, and carries a failed item", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_distance(server, @measured, parent)

    assert {:ok, [first, second]} =
             Direction.distance(
               client,
               [{116.481028, 39.989643}, {114.481028, 39.989643}],
               {114.465302, 40.004717}
             )

    assert first.origin_id == "1"
    assert first.dest_id == "1"
    assert first.distance == "12345"
    assert first.duration == "1200"
    assert first.info == nil
    assert first.code == nil

    # A failed item is data, not an envelope error: the call is still ok.
    assert second.origin_id == "2"
    assert second.info == "未知错误"
    assert second.code == "2"
    assert second.distance == "6789"
  end

  test "reads the same list when Amap nests it under result", %{server: server, client: client} do
    parent = self()
    expect_distance(server, @nested, parent)

    assert {:ok, [%Distance{distance: "12345"}]} =
             Direction.distance(client, [{116.481028, 39.989643}], {114.465302, 40.004717})
  end

  test "answers an empty list when Amap has no distance to give", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_distance(server, @none, parent)

    assert {:ok, []} =
             Direction.distance(client, [{116.481028, 39.989643}], {114.465302, 40.004717})
  end

  defp expect_distance(server, body, parent) do
    TestServer.expect_once(server, "GET", "/v3/distance", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, body}
    end)
  end
end
