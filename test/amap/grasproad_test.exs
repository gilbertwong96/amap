defmodule Amap.GrasproadTest do
  use ExUnit.Case, async: true

  alias Amap.Grasproad
  alias Amap.Grasproad.Point
  alias Amap.Grasproad.Result
  alias Amap.TestServer

  # The page's own sample body, re-shaped for the SDK's point map: the wire's
  # `x`/`y` are one `{lon, lat}` location here, and `ag`/`tm`/`sp` keep the page's
  # names. The first point's `tm` is the absolute instant; the rest are seconds
  # from it, which is the rule the page states.
  @pinned [
    %{location: {116.478928, 39.997761}, ag: 0, tm: 1_478_031_031, sp: 19},
    %{location: {116.478907, 39.998422}, ag: 0, tm: 2, sp: 10},
    %{location: {116.479384, 39.998546}, ag: 110, tm: 3, sp: 10},
    %{location: {116.481053, 39.998204}, ag: 120, tm: 4, sp: 10},
    %{location: {116.481793, 39.997868}, ag: 120, tm: 5, sp: 10},
    %{location: {116.482898, 39.998217}, ag: 30, tm: 6, sp: 10},
    %{location: {116.483789, 39.999063}, ag: 30, tm: 7, sp: 10},
    %{location: {116.484674, 39.999844}, ag: 30, tm: 8, sp: 10}
  ]

  # The response table's shape: `data{distance, points[]{x, y}}` under the Falcon
  # envelope. The page types none of the three values, so one fixture sends the
  # strings the older Web-service pages send and one sends the numbers the v4
  # bicycling live run saw.
  @corrected ~s({"errcode":0,"errmsg":"OK",) <>
               ~s("data":{"distance":"1234.5",) <>
               ~s("points":[{"x":"116.478928","y":"39.997761"},) <>
               ~s({"x":"116.478930","y":"39.997800"}]}})

  @corrected_numbers ~s({"errcode":10000,"errmsg":"OK",) <>
                       ~s("data":{"distance":1234,) <>
                       ~s("points":[{"x":116.478928,"y":39.997761}]}})

  # The page documents 30001 as 抓路失败, likely when the points are too few or too
  # sparse.
  @failed ~s({"errcode":30001,"errmsg":"FAILED","errdetail":"抓路失败"})

  setup do
    server = TestServer.start!()

    # The tsapi base URL points at a closed port on purpose: this endpoint answers
    # the Falcon envelope but lives on the Web service host, so a call that sent to
    # the tsapi host would fail in transport rather than passing quietly.
    client =
      Amap.new(
        key: "test-key",
        base_urls: %{restapi: "http://localhost:#{server.port}", tsapi: "http://localhost:1"}
      )

    {:ok, server: server, client: client}
  end

  test "posts the page's array form to the Web service host", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_driving(server, @corrected, parent)

    # Reaching the server at all is the assertion: the track host is closed above.
    assert {:ok, %Result{}} = Grasproad.driving(client, @pinned)

    assert_receive {:request, "POST", "/v4/grasproad/driving", headers, body, query}
    assert headers["content-type"] == "application/json"
    # The page says the 通用参数 belong in the query string, and `key` is the only one.
    assert URI.decode_query(query) == %{"key" => "test-key"}

    assert [
             %{"x" => 116.478928, "y" => 39.997761, "ag" => 0, "tm" => 1_478_031_031, "sp" => 19}
             | rest
           ] = JSON.decode!(body)

    assert Enum.count(rest) == 7
  end

  test "takes a single point as a one-point track", %{server: server, client: client} do
    parent = self()
    expect_driving(server, @corrected, parent)

    assert {:ok, %Result{}} = Grasproad.driving(client, hd(@pinned))

    assert_receive {:request, _method, _path, _headers, body, _query}

    assert JSON.decode!(body) == [
             %{"x" => 116.478928, "y" => 39.997761, "ag" => 0, "tm" => 1_478_031_031, "sp" => 19}
           ]
  end

  test "bounds the array at the page's 500 objects", %{server: server, client: client} do
    parent = self()
    expect_driving(server, @corrected, parent)

    assert {:ok, %Result{}} = Grasproad.driving(client, List.duplicate(hd(@pinned), 500))
    assert_receive {:request, _method, _path, _headers, body, _query}
    assert Enum.count(JSON.decode!(body)) == 500
  end

  test "refuses a track that is not one point or a list of them", %{client: client} do
    assert_raise ArgumentError, ~r/points must be a point map or a non-empty list/, fn ->
      Grasproad.driving(client, "116.478928,39.997761")
    end

    assert_raise ArgumentError, ~r/points must be a point map or a non-empty list/, fn ->
      Grasproad.driving(client, [])
    end

    assert_raise ArgumentError, ~r/each point must be a map/, fn ->
      Grasproad.driving(client, [hd(@pinned), "second"])
    end
  end

  test "enforces the page's 500-object ceiling", %{client: client} do
    assert_raise ArgumentError, ~r/:points must be between 1 and 500, got: 501/, fn ->
      Grasproad.driving(client, List.duplicate(hd(@pinned), 501))
    end
  end

  test "requires every field the page marks 必填", %{client: client} do
    for missing <- [:location, :ag, :tm, :sp] do
      point = Map.delete(hd(@pinned), missing)

      assert_raise ArgumentError, ~r/needs #{inspect(missing)}/, fn ->
        Grasproad.driving(client, point)
      end
    end

    assert_raise ArgumentError, ~r/:location must be a \{lon, lat\} pair/, fn ->
      Grasproad.driving(client, %{hd(@pinned) | location: "116.478928,39.997761"})
    end

    assert_raise ArgumentError, ~r/:ag must be a number/, fn ->
      Grasproad.driving(client, %{hd(@pinned) | ag: "0"})
    end

    assert_raise ArgumentError, ~r/:sp must be a number/, fn ->
      Grasproad.driving(client, %{hd(@pinned) | sp: "19"})
    end

    assert_raise ArgumentError, ~r/:tm must be/, fn ->
      Grasproad.driving(client, %{hd(@pinned) | tm: "1478031031"})
    end
  end

  test "takes a first-point DateTime but not a later one", %{server: server, client: client} do
    parent = self()
    expect_driving(server, @corrected, parent)

    first = hd(@pinned)
    later = List.last(@pinned)
    first = %{first | tm: DateTime.from_unix!(1_478_031_031)}

    assert {:ok, %Result{}} = Grasproad.driving(client, [first | tl(@pinned)])
    assert_receive {:request, _method, _path, _headers, body, _query}
    assert [%{"tm" => 1_478_031_031} | _] = JSON.decode!(body)

    # A later point's `tm` is a difference, so an absolute DateTime there would be
    # encoded as a difference and silently mean the wrong instant.
    assert_raise ArgumentError, ~r/only on the first point/, fn ->
      Grasproad.driving(client, [
        %{first | tm: DateTime.from_unix!(1_478_031_031)},
        %{later | tm: DateTime.from_unix!(1_478_031_032)}
      ])
    end
  end

  test "rejects a negative speed", %{client: client} do
    assert_raise ArgumentError, ~r/:sp must be a non-negative speed in km\/h/, fn ->
      Grasproad.driving(client, %{hd(@pinned) | sp: -1})
    end
  end

  test "encodes coordinates as JSON numbers at the page's six decimals", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_driving(server, @corrected, parent)

    assert {:ok, %Result{}} =
             Grasproad.driving(client, %{hd(@pinned) | location: {116.4789283, 39.9977614}})

    assert_receive {:request, _method, _path, _headers, body, _query}
    [point] = JSON.decode!(body)
    assert point["x"] == 116.478928
    assert point["y"] == 39.997761
    assert is_float(point["x"])
  end

  test "is not signed, because this page documents no sig", %{server: server} do
    # A private key on purpose: signing follows the host and envelope, so a call
    # wired as `:restapi` without `envelope: :tsapi` — the mistake this test exists
    # to catch — would sign, and the refutation below would bite.
    client =
      Amap.new(
        key: "test-key",
        private_key: "test-secret",
        base_urls: %{restapi: "http://localhost:#{server.port}", tsapi: "http://localhost:1"}
      )

    parent = self()
    expect_driving(server, @corrected, parent)

    assert {:ok, %Result{}} = Grasproad.driving(client, @pinned)

    assert_receive {:request, _method, _path, _headers, _body, query}
    assert URI.decode_query(query) == %{"key" => "test-key"}
  end

  test "maps the page's data payload, keeping each scalar as sent", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "POST", "/v4/grasproad/driving", fn _req ->
      {200, @corrected}
    end)

    assert {:ok, result} = Grasproad.driving(client, @pinned)
    assert result.distance == "1234.5"
    assert [%Point{} = first, %Point{} = second] = result.points
    assert first.x == "116.478928"
    assert first.y == "39.997761"
    assert second.x == "116.478930"
    assert second.y == "39.997800"
  end

  test "accepts the number-shaped v4 payload too, and the 10000 success code", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "POST", "/v4/grasproad/driving", fn _req ->
      {200, @corrected_numbers}
    end)

    assert {:ok, result} = Grasproad.driving(client, @pinned)
    assert result.distance == 1234
    assert [%Point{x: 116.478928, y: 39.997761}] = result.points
  end

  test "is total over missing and extra keys", %{server: server, client: client} do
    TestServer.expect_once(server, "POST", "/v4/grasproad/driving", fn _req ->
      {200, ~s({"errcode":0,"errmsg":"OK"})}
    end)

    assert {:ok, %Result{distance: nil, points: []}} = Grasproad.driving(client, @pinned)

    TestServer.expect_once(server, "POST", "/v4/grasproad/driving", fn _req ->
      {200, ~s({"errcode":0,"errmsg":"OK","data":{"distance":"12","extra":true}})}
    end)

    assert {:ok, %Result{distance: "12", points: []}} = Grasproad.driving(client, @pinned)

    TestServer.expect_once(server, "POST", "/v4/grasproad/driving", fn _req ->
      {200, ~s({"errcode":0,"errmsg":"OK","data":{"points":[{"z":1},"junk"]}})}
    end)

    assert {:ok, %Result{points: [%Point{x: nil, y: nil}]}} = Grasproad.driving(client, @pinned)
  end

  test "unwraps a data object the service wrapped in an array", %{server: server, client: client} do
    TestServer.expect_once(server, "POST", "/v4/grasproad/driving", fn _req ->
      {200, ~s({"errcode":0,"errmsg":"OK","data":[{"distance":"5","points":[]}]})}
    end)

    assert {:ok, %Result{distance: "5"}} = Grasproad.driving(client, @pinned)
  end

  test "answers a 30001 as a grasp-road failure", %{server: server, client: client} do
    TestServer.expect_once(server, "POST", "/v4/grasproad/driving", fn _req ->
      {200, @failed}
    end)

    assert {:error, %Amap.Error{} = error} =
             Grasproad.driving(client, [hd(@pinned), List.last(@pinned)])

    assert error.code == 30001
    assert error.reason == :grasproad_failed
    assert error.retry == :no
    assert error.family == :tsapi
    assert error.message == "FAILED"
    assert error.detail == "抓路失败"
  end

  defp expect_driving(server, body, parent) do
    TestServer.expect_once(server, "POST", "/v4/grasproad/driving", fn req ->
      send(parent, {:request, req.method, req.path, req.headers, req.body, req.query})
      {200, body}
    end)
  end
end
