defmodule Amap.Falcon.TraceDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  @named ~s({"errcode":10000,"errmsg":"OK","data":{"trid":20,"trname":"早晨一趟"}})

  # What Amap generates when the caller did not name the trace.
  @generated ~s({"errcode":10000,"errmsg":"OK","data":{"trid":21,"trname":"随机名字"}})

  setup_all do
    server = TestServer.start_doctest!()

    # The generated name is the answer only when the request left `trname` out;
    # sending it empty is not the same as omitting it.
    TestServer.expect(server, "POST", "/v1/track/trace/add", fn request ->
      body = URI.decode_query(request.body)

      cond do
        body["trname"] == "早晨一趟" -> {200, @named}
        not Map.has_key?(body, "trname") -> {200, @generated}
        true -> {404, "unexpected trace name"}
      end
    end)

    TestServer.expect(server, "POST", "/v1/track/trace/delete", fn request ->
      body = URI.decode_query(request.body)

      if body["trid"] == "20" and body["sid"] == "1000" and body["tid"] == "456" do
        {200, ~s({"errcode":10000,"errmsg":"OK"})}
      else
        {404, "unexpected delete parameters"}
      end
    end)

    :ok
  end

  doctest Amap.Falcon.Trace
end
