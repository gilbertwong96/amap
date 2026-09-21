defmodule Amap.Falcon.TerminalMonitorDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # A short track under the default road-snapping correction: Amap answers an
  # empty `data` body rather than a position.
  @empty ~s({"errcode":10000,"errmsg":"OK","data":[]})

  @point ~s({"errcode":10000,"errmsg":"OK",) <>
           ~s("data":{"location":"114.158,22.279","locatetime":1469817532000}})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v1/track/terminal/lastpoint", fn request ->
      case URI.decode_query(request.query)["correction"] do
        "n" -> {200, @point}
        nil -> {200, @empty}
      end
    end)

    :ok
  end

  doctest Amap.Falcon.TerminalMonitor
end
