defmodule Amap.ErrorDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  @refusal ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

  @suspended ~s({"errcode":10004,"errmsg":"ACCESS_TOO_FREQUENT",) <>
               ~s("errdetail":"the key is suspended for one minute"})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v3/ip", fn _request -> {200, @refusal} end)

    TestServer.expect(server, "GET", "/v1/track/service/list", fn _request ->
      {200, @suspended}
    end)

    TestServer.expect(server, "GET", "/v3/geocode/geo", fn _request ->
      {502, "<html>bad gateway</html>"}
    end)

    :ok
  end

  doctest Amap.Error
end
