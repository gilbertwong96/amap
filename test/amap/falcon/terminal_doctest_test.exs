defmodule Amap.Falcon.TerminalDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  @created ~s({"errcode":10000,"errmsg":"OK",) <>
             ~s("data":{"sid":1000,"tid":456,"name":"货车01",) <>
             ~s("props":{"plate":"粤B12345"}}})

  # count is Amap's for the whole result set, while the page holds two of the three
  # rows; the first row has never reported a position.
  @page ~s({"errcode":10000,"errmsg":"OK","data":{"count":3,"results":[) <>
          ~s({"sid":1000,"tid":456,"name":"货车01","locatetime":null},) <>
          ~s({"sid":1000,"tid":457,"name":"货车02","locatetime":1469817532}]}})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "POST", "/v1/track/terminal/add", fn _request ->
      {200, @created}
    end)

    TestServer.expect(server, "GET", "/v1/track/terminal/list", fn _request ->
      {200, @page}
    end)

    TestServer.expect(server, "POST", "/v1/track/terminal/update", fn _request ->
      {200, ~s({"errcode":10000,"errmsg":"OK"})}
    end)

    :ok
  end

  doctest Amap.Falcon.Terminal
end
