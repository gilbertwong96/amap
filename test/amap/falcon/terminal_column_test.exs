defmodule Amap.Falcon.TerminalColumnTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.TerminalColumn
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

  test "add/5 declares a field with its type", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "POST", "/v1/track/terminal/column/add", fn req ->
      send(parent, {:body, URI.decode_query(req.body)})
      {200, ~s({"errcode":10000,"errmsg":"OK"})}
    end)

    assert :ok = TerminalColumn.add(client, 1, "plate", :string)
    assert_receive {:body, body}
    assert body["column"] == "plate"
    assert body["type"] == "string"
    refute Map.has_key?(body, "list")
  end

  test "add/5 sends the searchable flag only when given", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "POST", "/v1/track/terminal/column/add", fn req ->
      send(parent, {:body, URI.decode_query(req.body)})
      {200, ~s({"errcode":10000,"errmsg":"OK"})}
    end)

    TerminalColumn.add(client, 1, "plate", :string, list: :y)
    assert_receive {:body, body}
    assert body["list"] == "y"
  end

  test "add/5 rejects a type or a flag Amap does not document", %{client: client} do
    assert_raise ArgumentError,
                 ~r/:type must be one of \[:string, :double, :int\], got: :boolean/,
                 fn ->
                   TerminalColumn.add(client, 1, "plate", :boolean)
                 end

    assert_raise ArgumentError, ~r/:list must be :y or :n, got: "yes"/, fn ->
      TerminalColumn.add(client, 1, "plate", :string, list: "yes")
    end
  end

  test "add/5 rejects a column name Amap would", %{client: client} do
    assert_raise ArgumentError, ~r/:column may only contain/, fn ->
      TerminalColumn.add(client, 1, "a b", :string)
    end
  end

  test "delete/3 and update/4 carry the field name", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "POST", "/v1/track/terminal/column/delete", fn req ->
      send(parent, {:delete, URI.decode_query(req.body)})
      {200, ~s({"errcode":10000,"errmsg":"OK"})}
    end)

    assert :ok = TerminalColumn.delete(client, 1, "plate")
    assert_receive {:delete, deleted}
    assert deleted["column"] == "plate"

    TestServer.expect_once(server, "POST", "/v1/track/terminal/column/update", fn req ->
      send(parent, {:update, URI.decode_query(req.body)})
      {200, ~s({"errcode":10000,"errmsg":"OK"})}
    end)

    assert :ok = TerminalColumn.update(client, 1, "plate", "licence")
    assert_receive {:update, updated}
    assert updated["column"] == "plate"
    assert updated["newcolumn"] == "licence"
  end

  test "list/2 returns the fields, without the searchable flag", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v1/track/terminal/column/list", fn req ->
      assert URI.decode_query(req.query)["sid"] == "1"

      {200,
       ~s({"errcode":10000,"errmsg":"OK","data":{"results":[{"column":"plate","type":"string"},{"column":"age","type":"int"}]}})}
    end)

    assert {:ok,
            [
              %TerminalColumn{column: "plate", type: "string", list: nil},
              %TerminalColumn{column: "age", type: "int"}
            ]} =
             TerminalColumn.list(client, 1)
  end
end
