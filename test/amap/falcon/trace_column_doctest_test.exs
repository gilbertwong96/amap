defmodule Amap.Falcon.TraceColumnDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  setup_all do
    server = TestServer.start_doctest!()

    # The trace-field path, which says `point`; the exact type word; and no
    # searchable flag, which trace fields do not have.
    TestServer.expect(server, "POST", "/v1/track/point/column/add", fn request ->
      body = URI.decode_query(request.body)

      if body["column"] == "driver" and body["type"] == "string" and
           not Map.has_key?(body, "list") do
        {200, ~s({"errcode":10000,"errmsg":"OK"})}
      else
        {404, "unexpected trace-field parameters"}
      end
    end)

    :ok
  end

  doctest Amap.Falcon.TraceColumn
end
