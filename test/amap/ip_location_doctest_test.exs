defmodule Amap.IpLocationDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # The examples in `Amap.IpLocation` name this port, because a doctest body has
  # no test context to draw a client from. The port is written in both places; a
  # mismatch fails the doctests here as a transport error rather than silently.
  @port 21_617

  @located ~s({"status":"1","info":"OK","infocode":"10000","province":"北京市",) <>
             ~s("city":"北京市","adcode":"110000",) <>
             ~s("rectangle":"116.0119343,39.66127144;116.7829835,40.2164962"})

  @unplaceable ~s({"status":"1","info":"OK","infocode":"10000",) <>
                 ~s("province":[],"city":[],"adcode":[],"rectangle":[]})

  @refusal ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

  setup_all do
    server = TestServer.start!(port: @port)

    TestServer.expect(server, "GET", "/v3/ip", fn request ->
      case URI.decode_query(request.query)["ip"] do
        "203.0.113.1" -> {200, @located}
        "198.51.100.7" -> {200, @unplaceable}
        nil -> {200, @refusal}
      end
    end)

    :ok
  end

  doctest Amap.IpLocation
end
