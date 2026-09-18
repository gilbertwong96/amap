defmodule Amap.Falcon.FenceStatusTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.FenceStatus
  alias Amap.Falcon.FenceStatus.Page
  alias Amap.TestServer

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

  defp arm(server, path, body) do
    parent = self()

    TestServer.expect_once(server, "GET", path, fn req ->
      send(parent, {:params, URI.decode_query(req.query)})
      {200, body}
    end)

    parent
  end

  test "terminal/4 answers whether a terminal is inside", %{server: server, client: client} do
    arm(
      server,
      "/v1/track/geofence/status/terminal",
      ~s({"errcode":10000,"errmsg":"OK","data":{"count":1,"results":[{"gfid":77,"gfname":"仓库","in":1,"location":"114.158,22.279","time":1789703117430}]}})
    )

    assert {:ok, %Page{count: 1, items: [status]}} = FenceStatus.terminal(client, 1, 456)

    assert %FenceStatus{gfid: 77, gfname: "仓库", in: true} = status
    assert status.location == {114.158, 22.279}
    assert status.time == 1_789_703_117_430

    assert_receive {:params, params}
    assert params["tid"] == "456"
    refute Map.has_key?(params, "gfids")
  end

  test "a terminal with no position is outside, with no location or time", %{
    server: server,
    client: client
  } do
    # Amap fills `in` with 0 and omits the other two entirely.
    arm(
      server,
      "/v1/track/geofence/status/terminal",
      ~s({"errcode":10000,"errmsg":"OK","data":{"count":1,"results":[{"gfid":77,"gfname":"仓库","in":0}]}})
    )

    assert {:ok, %Page{items: [status]}} = FenceStatus.terminal(client, 1, 456)
    assert status.in == false
    assert status.location == nil
    assert status.time == nil
  end

  test "location/4 asks about a coordinate, longitude first", %{server: server, client: client} do
    arm(
      server,
      "/v1/track/geofence/status/location",
      ~s({"errcode":10000,"errmsg":"OK","data":{"count":2,"results":[{"gfid":77,"gfname":"仓库","in":1},{"gfid":78,"gfname":"别的","in":0}]}})
    )

    assert {:ok, %Page{count: 2, items: [inside, outside]}} =
             FenceStatus.location(client, 1, {114.158, 22.279})

    assert inside.in == true
    assert outside.in == false

    assert_receive {:params, params}
    assert params["location"] == "114.158,22.279"
  end

  test "gfids narrows the answer and drops the paging that Amap would ignore", %{
    server: server,
    client: client
  } do
    arm(
      server,
      "/v1/track/geofence/status/terminal",
      ~s({"errcode":10000,"errmsg":"OK","data":{"count":0,"results":[]}})
    )

    FenceStatus.terminal(client, 1, 456, gfids: [77, 78], page: 3, pagesize: 20)

    assert_receive {:params, params}
    assert params["gfids"] == "77,78"
    refute Map.has_key?(params, "page")
    refute Map.has_key?(params, "pagesize")
  end

  test "validates the ranges it can", %{client: client} do
    assert_raise ArgumentError, ~r/:gfids must be between 1 and 100, got: 101/, fn ->
      FenceStatus.terminal(client, 1, 456, gfids: Enum.to_list(1..101))
    end

    assert_raise ArgumentError, ~r/:pagesize must be between 1 and 100, got: 101/, fn ->
      FenceStatus.location(client, 1, {1, 2}, pagesize: 101)
    end
  end
end
