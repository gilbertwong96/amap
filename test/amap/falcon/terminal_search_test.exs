defmodule Amap.Falcon.TerminalSearchTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.TerminalSearch
  alias Amap.Falcon.TerminalSearch.Location
  alias Amap.Falcon.TerminalSearch.Page
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

  defp arm(server, path, body \\ ~s({"errcode":0,"errmsg":"OK","data":{"count":0,"results":[]}})) do
    parent = self()

    TestServer.expect_once(server, "POST", path, fn req ->
      send(parent, {:body, URI.decode_query(req.body)})
      {200, body}
    end)

    parent
  end

  describe "search/4" do
    test "sends sid and keywords", %{server: server, client: client} do
      arm(server, "/v1/track/terminal/search")

      TerminalSearch.search(client, 42, "王师傅")

      assert_receive {:body, body}
      assert body["sid"] == "42"
      assert body["keywords"] == "王师傅"
    end

    test "encodes a filter as Amap's && and |-separated form", %{server: server, client: client} do
      arm(server, "/v1/track/terminal/search")

      TerminalSearch.search(client, 1, "王", filter: [name: ["王师傅", "张师傅"]])

      assert_receive {:body, body}
      assert body["filter"] == "name=王师傅|张师傅"
    end

    test "encodes a comparison filter and a custom field", %{server: server, client: client} do
      arm(server, "/v1/track/terminal/search")

      TerminalSearch.search(client, 1, "王",
        filter: [{"age", "30"}, lastloctime: {:>=, 1_469_817_532}]
      )

      assert_receive {:body, body}
      assert body["filter"] == "age=30&&lastloctime>=1469817532"
    end

    test "encodes sort, page and pagesize", %{server: server, client: client} do
      arm(server, "/v1/track/terminal/search")

      TerminalSearch.search(client, 1, "王", sort: {:lastloctime, :desc}, page: 2, pagesize: 100)

      assert_receive {:body, body}
      assert body["sortrule"] == "lastloctime:desc"
      assert body["page"] == "2"
      assert body["pagesize"] == "100"
    end

    test "omits the optional parameters it was not given", %{server: server, client: client} do
      arm(server, "/v1/track/terminal/search")

      TerminalSearch.search(client, 1, "王")

      assert_receive {:body, body}
      refute Map.has_key?(body, "filter")
      refute Map.has_key?(body, "sortrule")
      refute Map.has_key?(body, "page")
      refute Map.has_key?(body, "pagesize")
    end

    test "maps results into structs, with the location object and custom fields", %{
      server: server,
      client: client
    } do
      arm(
        server,
        "/v1/track/terminal/search",
        ~s({"errcode":0,"errmsg":"OK","data":{"count":9,"results":[{"tid":7,"name":"货车01","locatetime":1469817532,"location":{"latitude":22.279,"longitude":114.158,"speed":0,"accuracy":20},"props":{"age":30},"myfield":"custom"}]}})
      )

      assert {:ok, %Page{count: 9, items: [result]}} = TerminalSearch.search(client, 1, "王")
      assert result.tid == 7
      assert result.locatetime == 1_469_817_532
      assert result.props == %{"age" => 30}
      assert result.custom == %{"myfield" => "custom"}

      assert %Location{latitude: 22.279, longitude: 114.158, accuracy: 20, height: nil} =
               result.location
    end

    test "rejects an unencodable filter before any request is built", %{client: client} do
      assert_raise ArgumentError, ~r/unsupported filter value for lastloctime/, fn ->
        TerminalSearch.search(client, 1, "王", filter: [lastloctime: "yesterday"])
      end
    end

    test "rejects an unsupported sort", %{client: client} do
      assert_raise ArgumentError, ~r/unsupported sort/, fn ->
        TerminalSearch.search(client, 1, "王", sort: {:speed, :asc})
      end
    end

    test "rejects empty keywords", %{client: client} do
      assert_raise ArgumentError, ~r/:keywords must be a non-empty string/, fn ->
        TerminalSearch.search(client, 1, "")
      end
    end
  end

  describe "aroundsearch/4" do
    test "sends the centre latitude first, since that is this endpoint's wire format", %{
      server: server,
      client: client
    } do
      arm(server, "/v1/track/terminal/aroundsearch")

      TerminalSearch.aroundsearch(client, 1, {114.158, 22.279})

      assert_receive {:body, body}
      assert body["center"] == "22.279,114.158"
    end

    test "sends radius when given, and omits it so Amap's own default applies", %{
      server: server,
      client: client
    } do
      arm(server, "/v1/track/terminal/aroundsearch")

      TerminalSearch.aroundsearch(client, 1, {114.158, 22.279}, radius: 1000)
      assert_receive {:body, with_radius}
      assert with_radius["radius"] == "1000"

      arm(server, "/v1/track/terminal/aroundsearch")

      TerminalSearch.aroundsearch(client, 1, {114.158, 22.279})
      assert_receive {:body, without_radius}
      refute Map.has_key?(without_radius, "radius")
    end

    test "validates radius against Amap's documented range", %{client: client} do
      assert_raise ArgumentError, ~r/:radius must be between 1 and 5000, got: 0/, fn ->
        TerminalSearch.aroundsearch(client, 1, {114.158, 22.279}, radius: 0)
      end

      assert_raise ArgumentError, ~r/:radius must be between 1 and 5000, got: 5001/, fn ->
        TerminalSearch.aroundsearch(client, 1, {114.158, 22.279}, radius: 5001)
      end
    end
  end
end
