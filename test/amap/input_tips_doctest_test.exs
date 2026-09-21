defmodule Amap.InputTipsDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # Two kinds in one answer: the POI tip carries a location, the busline tip does not.
  @tips ~S"""
  {"status":"1","info":"OK","infocode":"10000","count":"2",
   "tips":{"tip":[
    {"id":"B000A83M61","name":"招商银行(北京分行)","district":"北京市朝阳区",
     "adcode":"110105","location":"116.45,39.93","address":"朝阳区望京街9号"},
    {"id":"BV10002739","name":"招商银行站","district":"北京市朝阳区","adcode":"110105"}
   ]}}
  """

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v3/assistant/inputtips", fn _request ->
      {200, @tips}
    end)

    :ok
  end

  doctest Amap.InputTips
end
