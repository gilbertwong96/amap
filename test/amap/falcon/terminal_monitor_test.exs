defmodule Amap.Falcon.TerminalMonitorTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.Position
  alias Amap.Falcon.TerminalMonitor
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

  test "sends sid and tid, leaving the optional parameters out", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v1/track/terminal/lastpoint", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, ~s({"errcode":0,"errmsg":"OK","data":{"location":"116.397428,39.90923"}})}
    end)

    TerminalMonitor.lastpoint(client, 42, 456)

    assert_receive {:query, query}
    assert query["sid"] == "42"
    assert query["tid"] == "456"
    refute Map.has_key?(query, "trid")
    refute Map.has_key?(query, "correction")
  end

  test "parses location into a lng,lat tuple", %{server: server, client: client} do
    for {wire, expected} <- [
          {"116.397428,39.90923", {116.397428, 39.90923}},
          {"114.158,22.279", {114.158, 22.279}}
        ] do
      TestServer.expect_once(server, "GET", "/v1/track/terminal/lastpoint", fn _req ->
        {200, ~s({"errcode":0,"errmsg":"OK","data":{"location":"#{wire}"}})}
      end)

      assert {:ok, %Position{location: ^expected}} = TerminalMonitor.lastpoint(client, 1, 1)
    end
  end

  test "leaves location nil when Amap sends something unparseable", %{
    server: server,
    client: client
  } do
    for wire <- [nil, "not,a,point", "abc,def"] do
      body =
        if is_nil(wire) do
          ~s({"errcode":0,"errmsg":"OK","data":{}})
        else
          ~s({"errcode":0,"errmsg":"OK","data":{"location":"#{wire}"}})
        end

      TestServer.expect_once(server, "GET", "/v1/track/terminal/lastpoint", fn _req ->
        {200, body}
      end)

      assert {:ok, %Position{location: nil}} = TerminalMonitor.lastpoint(client, 1, 1)
    end
  end

  test "maps the rest of the payload, keeping Amap's field names", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v1/track/terminal/lastpoint", fn _req ->
      {200,
       ~s({"errcode":0,"errmsg":"OK","data":{"location":"114.158,22.279","locatetime":1469817532000,"accuracy":20,"speed":40,"direction":120,"height":39,"props":{"age":30}}})}
    end)

    assert {:ok, position} = TerminalMonitor.lastpoint(client, 1, 1)
    assert position.locatetime == 1_469_817_532_000
    assert position.accuracy == 20
    assert position.speed == 40
    assert position.direction == 120
    assert position.height == 39
    assert position.props == %{"age" => 30}
  end

  test "sends correction and trid when given", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v1/track/terminal/lastpoint", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, ~s({"errcode":0,"errmsg":"OK","data":{}})}
    end)

    TerminalMonitor.lastpoint(client, 1, 1, trid: 99, correction: :n)

    assert_receive {:query, query}
    assert query["trid"] == "99"
    assert query["correction"] == "n"
  end

  test "rejects a correction mode Amap does not document", %{client: client} do
    assert_raise ArgumentError, ~r/:correction must be :driving or :n, got: :maybe/, fn ->
      TerminalMonitor.lastpoint(client, 1, 1, correction: :maybe)
    end
  end
end
