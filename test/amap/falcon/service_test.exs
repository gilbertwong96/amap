defmodule Amap.Falcon.ServiceTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.Service
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

  test "add/3 returns the created service", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "POST", "/v1/track/service/add", fn req ->
      send(parent, {:body, req.body})
      {200, ~s({"errcode":0,"errmsg":"OK","data":{"sid":123,"name":"车队A"}})}
    end)

    assert {:ok, %Service{sid: 123, name: "车队A", desc: nil}} = Service.add(client, "车队A")
    assert_receive {:body, body}
    assert URI.decode_query(body)["name"] == "车队A"
    assert URI.decode_query(body)["key"] == "test-key"
  end

  test "add/3 sends desc only when given", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "POST", "/v1/track/service/add", fn req ->
      send(parent, {:body, req.body})
      {200, ~s({"errcode":0,"errmsg":"OK","data":{"sid":1,"name":"A"}})}
    end)

    Service.add(client, "A", desc: "description")
    assert_receive {:body, body}
    assert URI.decode_query(body)["desc"] == "description"

    TestServer.expect_once(server, "POST", "/v1/track/service/add", fn req ->
      send(parent, {:no_desc, URI.decode_query(req.body)})
      {200, ~s({"errcode":0,"errmsg":"OK","data":{"sid":1,"name":"A"}})}
    end)

    Service.add(client, "A")
    assert_receive {:no_desc, body}
    refute Map.has_key?(body, "desc")
  end

  test "delete/2 returns {:ok, nil}, since the API sends no data", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "POST", "/v1/track/service/delete", fn _req ->
      {200, ~s({"errcode":0,"errmsg":"OK"})}
    end)

    assert {:ok, nil} = Service.delete(client, 123)
  end

  test "update/3 returns the name as it was before the change", %{server: server, client: client} do
    TestServer.expect_once(server, "POST", "/v1/track/service/update", fn _req ->
      {200, ~s({"errcode":0,"errmsg":"OK","data":{"sid":123,"name":"旧名字"}})}
    end)

    assert {:ok, %Service{sid: 123, name: "旧名字"}} = Service.update(client, 123, desc: "new")
  end

  test "update/3 with no fields raises rather than sending an empty update", %{
    server: _server,
    client: client
  } do
    assert_raise ArgumentError, ~r/at least one/, fn -> Service.update(client, 123, []) end
  end

  test "list/1 returns a list of services", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v1/track/service/list", fn _req ->
      {200,
       ~s({"errcode":0,"errmsg":"OK","data":{"results":[{"sid":1,"name":"A","desc":"d"},{"sid":2,"name":"B"}]}})}
    end)

    assert {:ok, [%Service{sid: 1, name: "A", desc: "d"}, %Service{sid: 2, name: "B", desc: nil}]} =
             Service.list(client)
  end

  test "an Amap error comes back as the error struct", %{server: server, client: client} do
    TestServer.expect_once(server, "POST", "/v1/track/service/add", fn _req ->
      {200, ~s({"errcode":20000,"errmsg":"INVALID_PARAMS"})}
    end)

    assert {:error, error} = Service.add(client, "A")
    assert error.reason == :invalid_params
    assert error.family == :tsapi
  end

  test "a bad name never reaches the network", %{server: _server, client: client} do
    assert_raise ArgumentError, ~r/may only contain/, fn -> Service.add(client, "bad name") end
  end
end
