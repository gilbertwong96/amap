defmodule Amap.Falcon.TerminalColumnDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # The list endpoint reports the name and the type only, so the searchable flag
  # is absent even for a field declared `list: :y`.
  @fields ~s({"errcode":10000,"errmsg":"OK",) <>
            ~s("data":{"results":[{"column":"plate","type":"string"}]}})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "POST", "/v1/track/terminal/column/add", fn _request ->
      {200, ~s({"errcode":10000,"errmsg":"OK"})}
    end)

    TestServer.expect(server, "GET", "/v1/track/terminal/column/list", fn _request ->
      {200, @fields}
    end)

    :ok
  end

  doctest Amap.Falcon.TerminalColumn
end
