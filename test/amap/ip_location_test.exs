defmodule Amap.IpLocationTest do
  use ExUnit.Case, async: true

  alias Amap.IpLocation
  alias Amap.TestServer

  @beijing ~s({"status":"1","info":"OK","infocode":"10000","province":"北京市",) <>
             ~s("city":"北京市","adcode":"110000",) <>
             ~s("rectangle":"116.0119343,39.66127144;116.7829835,40.2164962"})

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

  test "sends the key alone when no address is given", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/ip", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @beijing}
    end)

    assert {:ok, %IpLocation{}} = IpLocation.ip(client)
    assert_receive {:query, query}
    assert query["key"] == "test-key"
    refute Map.has_key?(query, "ip")
  end

  test "sends the address when one is given", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/ip", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @beijing}
    end)

    IpLocation.ip(client, ip: "114.247.50.2")

    assert_receive {:query, query}
    assert query["ip"] == "114.247.50.2"
  end

  test "maps the answer, keeping Amap's field names", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/ip", fn _req -> {200, @beijing} end)

    assert {:ok, ip_location} = IpLocation.ip(client, ip: "114.247.50.2")
    assert ip_location.province == "北京市"
    assert ip_location.city == "北京市"
    assert ip_location.adcode == "110000"

    assert ip_location.rectangle ==
             [{116.0119343, 39.66127144}, {116.7829835, 40.2164962}]
  end

  test "maps an address Amap cannot place to nil fields", %{server: server, client: client} do
    unplaceable =
      ~s({"status":"1","info":"OK","infocode":"10000",) <>
        ~s("province":[],"city":[],"adcode":[],"rectangle":[]})

    TestServer.expect_once(server, "GET", "/v3/ip", fn _req -> {200, unplaceable} end)

    assert {:ok, ip_location} = IpLocation.ip(client, ip: "8.8.8.8")
    assert ip_location.province == nil
    assert ip_location.city == nil
    assert ip_location.adcode == nil
    assert ip_location.rectangle == nil
  end

  test "rejects an address Amap could never resolve", %{client: client} do
    assert_raise ArgumentError, ~r/:ip must be an IPv4 address, got: "example\.com"/, fn ->
      IpLocation.ip(client, ip: "example.com")
    end

    assert_raise ArgumentError, ~r/:ip must be an IPv4 address, got: "2001:db8::1"/, fn ->
      IpLocation.ip(client, ip: "2001:db8::1")
    end

    assert_raise ArgumentError, ~r/:ip must be an IPv4 address, got: 12345/, fn ->
      IpLocation.ip(client, ip: 12_345)
    end
  end

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    refusal = ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

    TestServer.expect_once(server, "GET", "/v3/ip", fn _req -> {200, refusal} end)

    assert {:error, %Amap.Error{}} = IpLocation.ip(client)
  end
end
