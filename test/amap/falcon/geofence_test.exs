defmodule Amap.Falcon.GeofenceTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.Geofence
  alias Amap.Falcon.Geofence.Page
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

  defp arm(server, method, path, body) do
    parent = self()

    TestServer.expect_once(server, method, path, fn req ->
      params =
        case method do
          "POST" -> URI.decode_query(req.body)
          "GET" -> URI.decode_query(req.query)
        end

      send(parent, {:params, params})
      {200, body}
    end)

    parent
  end

  @created ~s({"errcode":10000,"errmsg":"OK","data":{"gfid":77}})

  describe "creating fences" do
    test "a circle sends its centre longitude-first", %{server: server, client: client} do
      arm(server, "POST", "/v1/track/geofence/add/circle", @created)

      assert {:ok, %Geofence{gfid: 77}} =
               Geofence.add_circle(client, 1, "仓库", center: {114.158, 22.279}, radius: 500)

      assert_receive {:params, params}
      assert params["name"] == "仓库"
      assert params["sid"] == "1"
      # Longitude first, unlike the terminal-search endpoints' centre.
      assert params["center"] == "114.158,22.279"
      assert params["radius"] == "500"
    end

    test "a polygon sends its ring longitude-first, and needs three vertices", %{
      server: server,
      client: client
    } do
      arm(server, "POST", "/v1/track/geofence/add/polygon", @created)

      ring = [{116.35, 39.98}, {116.36, 39.98}, {116.36, 39.99}]

      assert {:ok, %Geofence{gfid: 77}} = Geofence.add_polygon(client, 1, "区域", points: ring)

      assert_receive {:params, params}
      assert params["points"] == "116.35,39.98;116.36,39.98;116.36,39.99"
    end

    test "a polyline adds its buffer radius", %{server: server, client: client} do
      arm(server, "POST", "/v1/track/geofence/add/polyline", @created)

      route = [{116.35, 39.98}, {116.36, 39.98}]

      assert {:ok, %Geofence{}} =
               Geofence.add_polyline(client, 1, "走廊", points: route, bufferradius: 200)

      assert_receive {:params, params}
      assert params["points"] == "116.35,39.98;116.36,39.98"
      assert params["bufferradius"] == "200"
    end

    test "a district fence sends its adcode", %{server: server, client: client} do
      arm(server, "POST", "/v1/track/geofence/add/district", @created)

      assert {:ok, %Geofence{}} = Geofence.add_district(client, 1, "香港", adcode: "810000")

      assert_receive {:params, params}
      assert params["adcode"] == "810000"
    end

    test "desc is sent only when given", %{server: server, client: client} do
      arm(server, "POST", "/v1/track/geofence/add/circle", @created)

      Geofence.add_circle(client, 1, "仓库", center: {1, 2}, radius: 10, desc: "notes")
      assert_receive {:params, with_desc}
      assert with_desc["desc"] == "notes"

      arm(server, "POST", "/v1/track/geofence/add/circle", @created)

      Geofence.add_circle(client, 1, "仓库", center: {1, 2}, radius: 10)
      assert_receive {:params, without_desc}
      refute Map.has_key?(without_desc, "desc")
    end

    test "rejects a name Amap would, and a missing shape parameter", %{client: client} do
      assert_raise ArgumentError, ~r/:name may only contain/, fn ->
        Geofence.add_circle(client, 1, "a b", center: {1, 2}, radius: 10)
      end

      assert_raise ArgumentError, ~r/:center is required for this fence shape/, fn ->
        Geofence.add_circle(client, 1, "仓库", radius: 10)
      end

      assert_raise ArgumentError, ~r/:adcode is required/, fn ->
        Geofence.add_district(client, 1, "香港", [])
      end
    end

    test "rejects shape parameters outside Amap's ranges", %{client: client} do
      assert_raise ArgumentError, ~r/:radius must be between 1 and 50000, got: 0/, fn ->
        Geofence.add_circle(client, 1, "仓库", center: {1, 2}, radius: 0)
      end

      assert_raise ArgumentError, ~r/:radius must be between 1 and 50000, got: 50001/, fn ->
        Geofence.add_circle(client, 1, "仓库", center: {1, 2}, radius: 50_001)
      end

      assert_raise ArgumentError, ~r/:points must be between 3 and 100, got: 2/, fn ->
        Geofence.add_polygon(client, 1, "区域", points: [{1, 2}, {3, 4}])
      end

      assert_raise ArgumentError, ~r/:bufferradius must be between 1 and 300, got: 301/, fn ->
        Geofence.add_polyline(client, 1, "走廊", points: [{1, 2}, {3, 4}], bufferradius: 301)
      end
    end
  end

  describe "updating fences" do
    test "a circle update sends the gfid and the shape again", %{server: server, client: client} do
      arm(server, "POST", "/v1/track/geofence/update/circle", ~s({"errcode":10000,"errmsg":"OK"}))

      assert {:ok, nil} =
               Geofence.update_circle(client, 1, 77, "仓库", center: {114.158, 22.279}, radius: 600)

      assert_receive {:params, params}
      assert params["gfid"] == "77"
      assert params["name"] == "仓库"
      assert params["center"] == "114.158,22.279"
      assert params["radius"] == "600"
    end

    test "each update posts to its own shape's path", %{server: server, client: client} do
      for {fun, shape, opts} <- [
            {:update_polygon, "polygon", [points: [{1, 2}, {3, 4}, {5, 6}]]},
            {:update_polyline, "polyline", [points: [{1, 2}, {3, 4}], bufferradius: 100]},
            {:update_district, "district", [adcode: "810000"]}
          ] do
        arm(
          server,
          "POST",
          "/v1/track/geofence/update/#{shape}",
          ~s({"errcode":10000,"errmsg":"OK"})
        )

        assert {:ok, nil} = apply(Geofence, fun, [client, 1, 77, "名字", opts])
        assert_receive {:params, params}
        assert params["gfid"] == "77"
      end
    end

    test "an update still needs a name, and a shape parameter", %{client: client} do
      assert_raise ArgumentError, ~r/:name must be a non-empty string/, fn ->
        Geofence.update_circle(client, 1, 77, "", center: {1, 2}, radius: 10)
      end

      assert_raise ArgumentError, ~r/:radius is required/, fn ->
        Geofence.update_circle(client, 1, 77, "仓库", center: {1, 2})
      end
    end
  end

  describe "deleting and listing" do
    test "delete/3 joins ids with commas and answers the ones removed", %{
      server: server,
      client: client
    } do
      arm(
        server,
        "POST",
        "/v1/track/geofence/delete",
        ~s({"errcode":10000,"errmsg":"OK","data":{"gfids":[1,2]}})
      )

      assert {:ok, [1, 2]} = Geofence.delete(client, 1, [1, 2])

      assert_receive {:params, params}
      assert params["gfids"] == "1,2"
    end

    test "delete/3 with :all sends the sentinel and answers nothing", %{
      server: server,
      client: client
    } do
      arm(server, "POST", "/v1/track/geofence/delete", ~s({"errcode":10000,"errmsg":"OK"}))

      # Amap sends no data for #all, because there is nothing to enumerate.
      assert {:ok, nil} = Geofence.delete(client, 1, :all)
      assert_receive {:params, params}
      assert params["gfids"] == "#all"
    end

    test "delete/3 refuses a list Amap would silently truncate", %{client: client} do
      # Amap keeps the first 100 and does not fail, so 150 ids would look deleted.
      assert_raise ArgumentError, ~r/:gfids must be between 1 and 100, got: 101/, fn ->
        Geofence.delete(client, 1, Enum.to_list(1..101))
      end

      assert_raise ArgumentError, ~r/:gfids must be between 1 and 100, got: 0/, fn ->
        Geofence.delete(client, 1, [])
      end
    end

    test "list/2 maps a page, leaving the shape as a map", %{server: server, client: client} do
      arm(
        server,
        "GET",
        "/v1/track/geofence/list",
        ~s({"errcode":10000,"errmsg":"OK","data":{"count":7,"results":[{"gfid":77,"name":"仓库","desc":"north","shape":{"center":"114.158,22.279","radius":500},"createtime":1789703117430,"modifytime":1789703117430}]}})
      )

      assert {:ok, %Page{count: 7, items: [fence]}} = Geofence.list(client, 1, outputshape: true)

      assert %Geofence{gfid: 77, name: "仓库", desc: "north", createtime: 1_789_703_117_430} = fence
      assert is_map(fence.shape)

      assert_receive {:params, params}
      assert params["outputshape"] == "1"
      assert params["sid"] == "1"
    end

    test "passing gfids turns pagination off, so neither page parameter is sent", %{
      server: server,
      client: client
    } do
      arm(
        server,
        "GET",
        "/v1/track/geofence/list",
        ~s({"errcode":10000,"errmsg":"OK","data":{"count":0,"results":[]}})
      )

      Geofence.list(client, 1, gfids: [77, 78])

      assert_receive {:params, params}
      assert params["gfids"] == "77,78"
      refute Map.has_key?(params, "page")
      refute Map.has_key?(params, "pagesize")
    end

    test "list/2 validates its ranges", %{client: client} do
      assert_raise ArgumentError, ~r/:pagesize must be between 1 and 100, got: 101/, fn ->
        Geofence.list(client, 1, pagesize: 101)
      end

      assert_raise ArgumentError, ~r/:gfids must be between 1 and 100/, fn ->
        Geofence.list(client, 1, gfids: Enum.to_list(1..101))
      end

      assert_raise ArgumentError, ~r/expected a boolean, got: "yes"/, fn ->
        Geofence.list(client, 1, outputshape: "yes")
      end
    end
  end

  test "shapes/0 lists the four shapes this module builds" do
    assert Geofence.shapes() == [:circle, :polygon, :polyline, :district]
  end
end
