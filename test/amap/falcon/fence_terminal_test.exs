defmodule Amap.Falcon.FenceTerminalTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.FenceTerminal
  alias Amap.Falcon.FenceTerminal.Page
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

  test "bind/4 sends the ids and answers the ones bound", %{server: server, client: client} do
    # Amap answers fences' ids as numbers and terminals' as strings, so both shapes
    # are decoded here.
    arm(
      server,
      "POST",
      "/v1/track/geofence/terminal/bind",
      ~s({"errcode":10000,"errmsg":"OK","data":{"tids":[1,"2"]}})
    )

    assert {:ok, [1, 2]} = FenceTerminal.bind(client, 1, 77, [1, 2])

    assert_receive {:params, params}
    assert params["gfid"] == "77"
    assert params["tids"] == "1,2"
  end

  test "unbind/4 with ids answers the ones removed", %{server: server, client: client} do
    arm(
      server,
      "POST",
      "/v1/track/geofence/terminal/unbind",
      ~s({"errcode":10000,"errmsg":"OK","data":{"tids":[1]}})
    )

    assert {:ok, [1]} = FenceTerminal.unbind(client, 1, 77, [1])
  end

  test "unbind/4 with :all sends the sentinel and answers nothing", %{
    server: server,
    client: client
  } do
    arm(server, "POST", "/v1/track/geofence/terminal/unbind", ~s({"errcode":10000,"errmsg":"OK"}))

    assert :ok = FenceTerminal.unbind(client, 1, 77, :all)

    assert_receive {:params, params}
    assert params["tids"] == "#all"
  end

  test "bind/4 refuses a list Amap would truncate", %{client: client} do
    assert_raise ArgumentError, ~r/:tids must be between 1 and 100, got: 101/, fn ->
      FenceTerminal.bind(client, 1, 77, Enum.to_list(1..101))
    end
  end

  test "list/4 maps a page of bound terminals", %{server: server, client: client} do
    arm(
      server,
      "GET",
      "/v1/track/geofence/terminal/list",
      ~s({"errcode":10000,"errmsg":"OK","data":{"count":2,"results":[{"tid":1,"tname":"货车01"},{"tid":2,"tname":"货车02"}]}})
    )

    assert {:ok,
            %Page{
              count: 2,
              items: [%FenceTerminal{tid: 1, tname: "货车01"}, %FenceTerminal{tid: 2}]
            }} =
             FenceTerminal.list(client, 1, 77)

    assert_receive {:params, params}
    assert params["gfid"] == "77"
    refute Map.has_key?(params, "page")
  end

  test "list/4 validates the page size", %{client: client} do
    assert_raise ArgumentError, ~r/:pagesize must be between 1 and 100, got: 101/, fn ->
      FenceTerminal.list(client, 1, 77, pagesize: 101)
    end
  end

  test "an Amap error comes back as the error struct", %{server: server, client: client} do
    arm(
      server,
      "POST",
      "/v1/track/geofence/terminal/bind",
      ~s({"errcode":20000,"errmsg":"INVALID_PARAMS"})
    )

    assert {:error, error} = FenceTerminal.bind(client, 1, 77, [1])
    assert error.reason == :invalid_params
  end
end
