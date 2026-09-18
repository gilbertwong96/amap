defmodule Amap.Falcon.TraceColumnTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.TraceColumn
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

  # Amap's paths for trace fields say `point`, which is a trap worth pinning
  # rather than remembering: the module is named after the domain, the wire is not.
  test "add/4 posts to point/column, despite these being trace fields", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "POST", "/v1/track/point/column/add", fn req ->
      send(parent, {:body, URI.decode_query(req.body)})
      {200, ~s({"errcode":10000,"errmsg":"OK"})}
    end)

    assert {:ok, nil} = TraceColumn.add(client, 1, "driver", :string)
    assert_receive {:body, body}
    assert body["column"] == "driver"
    assert body["type"] == "string"
    # No searchable flag for trace fields, unlike terminal ones.
    refute Map.has_key?(body, "list")
  end

  test "add/4 rejects a type Amap does not document", %{client: client} do
    assert_raise ArgumentError, ~r/:type must be one of \[:string, :double, :int\]/, fn ->
      TraceColumn.add(client, 1, "driver", :text)
    end
  end

  test "delete/3 and update/4 carry the field name", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "POST", "/v1/track/point/column/delete", fn req ->
      send(parent, {:delete, URI.decode_query(req.body)})
      {200, ~s({"errcode":10000,"errmsg":"OK"})}
    end)

    assert {:ok, nil} = TraceColumn.delete(client, 1, "driver")
    assert_receive {:delete, deleted}
    assert deleted["column"] == "driver"

    TestServer.expect_once(server, "POST", "/v1/track/point/column/update", fn req ->
      send(parent, {:update, URI.decode_query(req.body)})
      {200, ~s({"errcode":10000,"errmsg":"OK"})}
    end)

    assert {:ok, nil} = TraceColumn.update(client, 1, "driver", "driverName")
    assert_receive {:update, updated}
    assert updated["newcolumn"] == "driverName"
  end

  test "list/2 returns the fields", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v1/track/point/column/list", fn _req ->
      {200,
       ~s({"errcode":10000,"errmsg":"OK","data":{"results":[{"column":"driver","type":"string"}]}})}
    end)

    assert {:ok, [%TraceColumn{column: "driver", type: "string"}]} = TraceColumn.list(client, 1)
  end
end
