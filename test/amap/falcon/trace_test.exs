defmodule Amap.Falcon.TraceTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.Trace
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

  test "add/4 returns the created trace", %{server: server, client: client} do
    TestServer.expect_once(server, "POST", "/v1/track/trace/add", fn _req ->
      {200, ~s({"errcode":10000,"errmsg":"OK","data":{"trid":20,"trname":"早晨一趟"}})}
    end)

    assert {:ok, %Trace{trid: 20, trname: "早晨一趟"}} = Trace.add(client, 1, 456, trname: "早晨一趟")
  end

  test "add/4 sends trname only when given, and returns Amap's generated one otherwise", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "POST", "/v1/track/trace/add", fn req ->
      send(parent, {:body, URI.decode_query(req.body)})
      {200, ~s({"errcode":10000,"errmsg":"OK","data":{"trid":21,"trname":"随机名字"}})}
    end)

    assert {:ok, %Trace{trid: 21, trname: "随机名字"}} = Trace.add(client, 1, 456)
    assert_receive {:body, body}
    refute Map.has_key?(body, "trname")
    assert body["sid"] == "1"
    assert body["tid"] == "456"
  end

  test "delete/4 returns :ok", %{server: server, client: client} do
    TestServer.expect_once(server, "POST", "/v1/track/trace/delete", fn req ->
      assert URI.decode_query(req.body)["trid"] == "20"
      {200, ~s({"errcode":10000,"errmsg":"OK"})}
    end)

    assert :ok = Trace.delete(client, 1, 456, 20)
  end

  test "an invalid trname raises before any request is built", %{client: client} do
    assert_raise ArgumentError, ~r/:trname may only contain/, fn ->
      Trace.add(client, 1, 456, trname: "a b")
    end
  end

  test "an Amap error comes back as the error struct", %{server: server, client: client} do
    TestServer.expect_once(server, "POST", "/v1/track/trace/add", fn _req ->
      {200, ~s({"errcode":20051,"errmsg":"TERMINAL_NOT_FOUND"})}
    end)

    assert {:error, error} = Trace.add(client, 1, 456)
    assert error.reason == :terminal_not_found
    assert error.family == :tsapi
  end
end
