defmodule Amap.Falcon.TerminalSearchDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  @found ~s({"errcode":10000,"errmsg":"OK","data":{"count":1,"results":[) <>
           ~s({"tid":456,"name":"王师傅","locatetime":1469817532,) <>
           ~s("location":{"latitude":22.279,"longitude":114.158,"speed":0,"accuracy":20},) <>
           ~s("props":{"plate":"粤B12345"},"myfield":"custom"}]}})

  @around ~s({"errcode":10000,"errmsg":"OK","data":{"count":1,"results":[) <>
            ~s({"tid":457,"name":"货车01","distance":1200,"locatetime":1469817532,) <>
            ~s("location":{"latitude":22.279,"longitude":114.158}}]}})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "POST", "/v1/track/terminal/search", fn request ->
      body = URI.decode_query(request.body)

      if body["filter"] == "name=王师傅|张师傅&&lastloctime>=1469817532" and
           body["sortrule"] == "lastloctime:desc" do
        {200, @found}
      else
        {404, "unexpected search parameters"}
      end
    end)

    TestServer.expect(server, "POST", "/v1/track/terminal/aroundsearch", fn request ->
      body = URI.decode_query(request.body)

      if body["center"] == "22.279,114.158" and body["radius"] == "1000" do
        {200, @around}
      else
        {404, "unexpected aroundsearch parameters"}
      end
    end)

    :ok
  end

  doctest Amap.Falcon.TerminalSearch
end
