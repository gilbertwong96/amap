defmodule Amap.Falcon.GrasproadDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # A corrected point may carry nothing but its location, and degradedParams is
  # the inverted wire flag: 0 means the accuracy filter was still applied.
  @one_track ~s({"errcode":10000,"errmsg":"OK",) <>
               ~s("data":{"counts":1,"tracks":[{"trid":20,"counts":1,) <>
               ~s("points":[{"location":"114.1589,22.2799"}]}],) <>
               ~s("degradedParams":{"threshold":0}}})

  setup_all do
    server = TestServer.start_doctest!()

    # The correction string is Correction's documented order, and the call must
    # read by trid rather than by a window.
    TestServer.expect(server, "GET", "/v1/track/terminal/trsearch", fn request ->
      query = URI.decode_query(request.query)

      if query["trid"] == "20" and
           query["correction"] == "denoise=1,mapmatch=1,attribute=0,threshold=0,mode=driving" do
        {200, @one_track}
      else
        {404, "unexpected trsearch parameters"}
      end
    end)

    # An account without the ticket: a service refusal, not a result.
    TestServer.expect(server, "POST", "/v1/track/terminal/roaddata", fn _request ->
      {200, ~s({"errcode":20050,"errmsg":"SERVICE_NOT_FOUND"})}
    end)

    :ok
  end

  doctest Amap.Falcon.Grasproad
end
