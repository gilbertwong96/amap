defmodule Amap.Falcon.PointTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.Point
  alias Amap.Falcon.Point.Upload
  alias Amap.Falcon.Point.UploadError
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

  defp arm(server, body) do
    parent = self()

    TestServer.expect_once(server, "POST", "/v1/track/point/upload", fn req ->
      send(parent, {:body, URI.decode_query(req.body)})
      {200, body}
    end)

    parent
  end

  defp sent_points do
    assert_receive {:body, body}
    assert %{"sid" => "1", "tid" => "456", "trid" => "20", "points" => points_json} = body
    JSON.decode!(points_json)
  end

  test "encodes a location tuple and a DateTime, with the optional fields left out", %{
    server: server,
    client: client
  } do
    arm(server, ~s({"errcode":10000,"errmsg":"OK","data":{"errorpoints":[]}}))

    assert {:ok, %Upload{errorpoints: []}} =
             Point.upload(client, 1, 456, 20, [
               %{location: {114.158, 22.279}, locatetime: ~U[2026-09-17 12:00:00Z]}
             ])

    assert [point] = sent_points()
    assert point["location"] == "114.158,22.279"
    assert point["locatetime"] == DateTime.to_unix(~U[2026-09-17 12:00:00Z], :millisecond)
    refute Map.has_key?(point, "speed")
    refute Map.has_key?(point, "props")
  end

  test "carries the optional fields, with props JSON-encoded", %{server: server, client: client} do
    arm(server, ~s({"errcode":10000,"errmsg":"OK","data":{"errorpoints":[]}}))

    Point.upload(client, 1, 456, 20, [
      %{
        location: {114.158, 22.279},
        locatetime: 1_789_703_113_430,
        speed: 40.5,
        direction: 120,
        height: 39,
        accuracy: 20,
        props: %{"driver" => "abc"}
      }
    ])

    assert [point] = sent_points()
    assert point["locatetime"] == 1_789_703_113_430
    assert point["speed"] == 40.5
    assert point["direction"] == 120
    assert point["height"] == 39
    assert point["accuracy"] == 20
    assert point["props"] == ~s({"driver":"abc"})
  end

  test "encodes every point of a batch", %{server: server, client: client} do
    arm(server, ~s({"errcode":10000,"errmsg":"OK","data":{"errorpoints":[]}}))

    Point.upload(client, 1, 456, 20, [
      %{location: {114.158, 22.279}, locatetime: 1},
      %{location: {114.1583, 22.2793}, locatetime: 2}
    ])

    assert [first, second] = sent_points()
    assert first["location"] == "114.158,22.279"
    assert second["location"] == "114.1583,22.2793"
  end

  test "maps a partial success into errorpoints, which is still a successful call", %{
    server: server,
    client: client
  } do
    # `20100` is what Amap answers when only some points were stored; the valid
    # ones are kept, and this list says which to send again.
    arm(
      server,
      ~s({"errcode":20100,"errmsg":"PARTIAL_SUCCESS","data":{"errorpoints":[{"_err_point_index":"3","_param_err_info":"invalid location","location":"oops"}]}})
    )

    assert {:ok, %Upload{errorpoints: [error]}} =
             Point.upload(client, 1, 456, 20, [
               %{location: {114.158, 22.279}, locatetime: 1},
               %{location: {114.1583, 22.2793}, locatetime: 2}
             ])

    assert %UploadError{index: "3", message: "invalid location"} = error
    assert error.raw == %{"location" => "oops"}
  end

  test "accepts a single errorpoints object, since Amap documents it loosely", %{
    server: server,
    client: client
  } do
    arm(
      server,
      ~s({"errcode":20101,"errmsg":"NOTHING_SUCCESS","data":{"errorpoints":{"_err_point_index":"1","_param_err_info":"missing locatetime"}}})
    )

    assert {:error, error} =
             Point.upload(client, 1, 456, 20, [%{location: {1, 2}, locatetime: 1}])

    assert error.reason == :nothing_success
  end

  test "rejects a batch size Amap does not accept", %{client: client} do
    point = %{location: {114.158, 22.279}, locatetime: 1}

    assert_raise ArgumentError, ~r/:points must be between 1 and 100, got: 0/, fn ->
      Point.upload(client, 1, 456, 20, [])
    end

    assert_raise ArgumentError, ~r/:points must be between 1 and 100, got: 101/, fn ->
      Point.upload(client, 1, 456, 20, List.duplicate(point, 101))
    end
  end

  test "rejects a point missing location or locatetime", %{client: client} do
    assert_raise ArgumentError, ~r/each point needs :location/, fn ->
      Point.upload(client, 1, 456, 20, [%{locatetime: 1}])
    end

    assert_raise ArgumentError, ~r/each point needs :locatetime/, fn ->
      Point.upload(client, 1, 456, 20, [%{location: {1, 2}}])
    end
  end

  test "rejects a locatetime that is neither a DateTime nor milliseconds", %{client: client} do
    assert_raise ArgumentError, ~r/:locatetime must be a DateTime or unix milliseconds/, fn ->
      Point.upload(client, 1, 456, 20, [%{location: {1, 2}, locatetime: "noon"}])
    end
  end

  test "rejects a point that is not a map, and props that are not one either", %{client: client} do
    assert_raise ArgumentError, ~r/each point must be a map, got: :nope/, fn ->
      Point.upload(client, 1, 456, 20, [:nope])
    end

    assert_raise ArgumentError, ~r/:props must be a map, got: "driver=abc"/, fn ->
      Point.upload(client, 1, 456, 20, [%{location: {1, 2}, locatetime: 1, props: "driver=abc"}])
    end
  end

  describe "parse_location/1" do
    test "reads Amap's lon,lat string" do
      assert Point.parse_location("116.397428,39.90923") == {116.397428, 39.90923}
      assert Point.parse_location("114.158,22.279") == {114.158, 22.279}
    end

    test "returns nil rather than raising for anything it cannot read" do
      assert Point.parse_location(nil) == nil
      assert Point.parse_location("not,a,point") == nil
      assert Point.parse_location("abc,def") == nil
      assert Point.parse_location(123) == nil
    end
  end
end
