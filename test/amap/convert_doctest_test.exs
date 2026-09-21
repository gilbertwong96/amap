defmodule Amap.ConvertDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # The default is "do not convert", so the stand-in reads the points back as they
  # were sent; the :gps branch answers shifted ones.
  @unchanged ~s({"status":"1","info":"OK","infocode":"10000",) <>
               ~s("locations":"116.481499,39.990475"})

  @converted ~s({"status":"1","info":"OK","infocode":"10000",) <>
               ~s("locations":"116.487001,39.992123"})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v3/assistant/coordinate/convert", fn request ->
      query = URI.decode_query(request.query)

      if Map.has_key?(query, "coordsys") do
        {200, @converted}
      else
        {200, @unchanged}
      end
    end)

    :ok
  end

  doctest Amap.Convert
end
