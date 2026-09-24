defmodule Amap.Falcon.TerminalTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.Terminal
  alias Amap.Falcon.Terminal.Page
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

  test "add/4 returns the created terminal", %{server: server, client: client} do
    TestServer.expect_once(server, "POST", "/v1/track/terminal/add", fn _req ->
      {200, ~s({"errcode":0,"errmsg":"OK","data":{"sid":1,"tid":456,"name":"货车01"}})}
    end)

    assert {:ok, %Terminal{sid: 1, tid: 456, name: "货车01", desc: nil}} =
             Terminal.add(client, 1, "货车01")
  end

  test "add/4 sends props as a JSON string, and omits them otherwise", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "POST", "/v1/track/terminal/add", fn req ->
      send(parent, {:with_props, URI.decode_query(req.body)})
      {200, ~s({"errcode":0,"errmsg":"OK","data":{"sid":1,"tid":1,"name":"A"}})}
    end)

    Terminal.add(client, 1, "A", props: %{"age" => 30})
    assert_receive {:with_props, body}
    assert body["props"] == ~s({"age":30})

    TestServer.expect_once(server, "POST", "/v1/track/terminal/add", fn req ->
      send(parent, {:without_props, URI.decode_query(req.body)})
      {200, ~s({"errcode":0,"errmsg":"OK","data":{"sid":1,"tid":1,"name":"A"}})}
    end)

    Terminal.add(client, 1, "A")
    assert_receive {:without_props, body}
    refute Map.has_key?(body, "props")
  end

  test "add/4 raises for props that are not a map", %{client: client} do
    assert_raise ArgumentError, ~r/:props must be a map, got: "age=30"/, fn ->
      Terminal.add(client, 1, "A", props: "age=30")
    end
  end

  test "add/4 rejects a desc Amap would reject", %{client: client} do
    assert_raise ArgumentError, ~r/:desc may only contain/, fn ->
      Terminal.add(client, 1, "A", desc: "a b")
    end

    assert_raise ArgumentError, ~r/:desc must be at most 128 characters/, fn ->
      Terminal.add(client, 1, "A", desc: String.duplicate("a", 129))
    end
  end

  test "delete/3 returns :ok", %{server: server, client: client} do
    TestServer.expect_once(server, "POST", "/v1/track/terminal/delete", fn _req ->
      {200, ~s({"errcode":0,"errmsg":"OK"})}
    end)

    assert :ok = Terminal.delete(client, 1, 456)
  end

  test "update/4 sends only the fields it is given", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "POST", "/v1/track/terminal/update", fn req ->
      send(parent, {:body, URI.decode_query(req.body)})
      {200, ~s({"errcode":0,"errmsg":"OK"})}
    end)

    assert :ok = Terminal.update(client, 1, 456, props: %{"age" => 31})
    assert_receive {:body, body}
    assert body["props"] == ~s({"age":31})
    refute Map.has_key?(body, "desc")
  end

  test "update/4 accepts name, which this endpoint documents as modifiable", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "POST", "/v1/track/terminal/update", fn req ->
      send(parent, {:body, URI.decode_query(req.body)})
      {200, ~s({"errcode":10000,"errmsg":"OK"})}
    end)

    assert :ok = Terminal.update(client, 1, 456, name: "新名字")
    assert_receive {:body, body}
    assert body["name"] == "新名字"
  end

  test "update/4 passes an empty string through, which clears the field", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "POST", "/v1/track/terminal/update", fn req ->
      send(parent, {:body, URI.decode_query(req.body)})
      {200, ~s({"errcode":10000,"errmsg":"OK"})}
    end)

    assert :ok = Terminal.update(client, 1, 456, desc: "")
    assert_receive {:body, body}
    assert body["desc"] == ""
  end

  test "update/4 rejects a non-string desc through the public API", %{client: client} do
    # Reachable at runtime even though the validators' inferred types are
    # narrower: a keyword value is a term() to the compiler.
    assert_raise ArgumentError, ~r/:desc must be a string/, fn ->
      Terminal.update(client, 1, 456, desc: 42)
    end
  end

  test "update/4 with no fields raises", %{client: client} do
    assert_raise ArgumentError, ~r/at least one/, fn -> Terminal.update(client, 1, 456, []) end
  end

  test "list/2 returns a Page with Amap's count, and nil for a null locatetime", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v1/track/terminal/list", fn req ->
      assert URI.decode_query(req.query)["sid"] == "1"

      {200,
       ~s({"errcode":0,"errmsg":"OK","data":{"count":2,"results":[{"tid":1,"name":"A","locatetime":null},{"tid":2,"name":"B","locatetime":1469817532}]}})}
    end)

    assert {:ok, %Page{count: 2, items: [first, second]}} = Terminal.list(client, 1)
    assert first.name == "A"
    assert first.locatetime == nil
    assert second.locatetime == 1_469_817_532
  end

  test "list/2 coerces a string tid, since the docs claim it is one there", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v1/track/terminal/list", fn _req ->
      {200,
       ~s({"errcode":10000,"errmsg":"OK","data":{"count":1,"results":[{"tid":"2121235591","name":"A"}]}})}
    end)

    assert {:ok, %Page{items: [%Terminal{tid: 2_121_235_591}]}} = Terminal.list(client, 1)
  end

  test "list/2 validates the page number before requesting", %{client: client} do
    assert_raise ArgumentError, ~r/:page must be between 1 and 1000000/, fn ->
      Terminal.list(client, 1, page: 0)
    end
  end
end
