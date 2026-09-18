defmodule Amap.ConvertTest do
  use ExUnit.Case, async: true

  alias Amap.Convert
  alias Amap.TestServer

  @converted ~s({"status":"1","info":"OK","infocode":"10000",) <>
               ~s("locations":"116.481499,39.990475;114.1589,22.2799"})

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

  test "sends the points pipe-separated, as this endpoint takes them", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/assistant/coordinate/convert", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @converted}
    end)

    assert {:ok, %Convert{}} =
             Convert.convert(client, [{116.481499, 39.990475}, {114.1589, 22.2799}],
               coordsys: :gps
             )

    assert_receive {:query, query}
    assert query["key"] == "test-key"
    assert query["locations"] == "116.481499,39.990475|114.1589,22.2799"
    assert query["coordsys"] == "gps"
  end

  test "leaves coordsys out when it was not given", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/assistant/coordinate/convert", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @converted}
    end)

    Convert.convert(client, [{116.481499, 39.990475}])

    assert_receive {:query, query}
    refute Map.has_key?(query, "coordsys")
    assert query["locations"] == "116.481499,39.990475"
  end

  test "parses the answer's semicolon-separated points", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/assistant/coordinate/convert", fn _req ->
      {200, @converted}
    end)

    assert {:ok, convert} =
             Convert.convert(client, [{116.481499, 39.990475}, {114.1589, 22.2799}],
               coordsys: :gps
             )

    assert convert.locations == [{116.481499, 39.990475}, {114.1589, 22.2799}]
  end

  test "formats coordinates to the six decimals Amap accepts", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/assistant/coordinate/convert", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @converted}
    end)

    Convert.convert(client, [{116.48149912345, 39.9904759999}], coordsys: :gps)

    assert_receive {:query, query}
    assert query["locations"] == "116.481499,39.990476"
  end

  test "rejects a system Amap does not document", %{client: client} do
    assert_raise ArgumentError, ~r/:coordsys must be one of/, fn ->
      Convert.convert(client, [{116.48, 39.99}], coordsys: :wgs84)
    end
  end

  test "rejects an empty list and more than forty points", %{client: client} do
    assert_raise ArgumentError, ~r/:locations must not be empty/, fn ->
      Convert.convert(client, [])
    end

    assert_raise ArgumentError, ~r/:locations count must be between 1 and 40, got: 41/, fn ->
      Convert.convert(client, Enum.map(1..41, &{&1 / 10, 39.99}))
    end
  end

  test "rejects a list that is not pairs of numbers", %{client: client} do
    assert_raise ArgumentError, ~r/:locations must be a list of \{lon, lat\} tuples/, fn ->
      Convert.convert(client, [[116.48, 39.99]])
    end

    assert_raise ArgumentError, ~r/:locations must be a list of \{lon, lat\} tuples/, fn ->
      Convert.convert(client, [{"116.48", "39.99"}])
    end
  end

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    refusal = ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

    TestServer.expect_once(server, "GET", "/v3/assistant/coordinate/convert", fn _req ->
      {200, refusal}
    end)

    assert {:error, %Amap.Error{}} = Convert.convert(client, [{116.48, 39.99}])
  end
end
