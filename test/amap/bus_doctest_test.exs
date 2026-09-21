defmodule Amap.BusDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # `city` is optional on the keyword searches: leaving it out searches the whole
  # country, so the stand-in answers lines from more than one city.
  @nationwide ~S"""
  {"status":"1","info":"OK","infocode":"10000","count":"2",
   "suggestion":{"keywords":[],"cities":[]},"buslines":[
    {"id":"110100010042","type":"地铁线路","name":"地铁1号线(苹果园--四惠东)",
     "citycode":"010","start_stop":"苹果园","end_stop":"四惠东"},
    {"id":"290100010042","type":"地铁线路","name":"地铁1号线(后卫寨--纺织城)",
     "citycode":"029","start_stop":"后卫寨","end_stop":"纺织城"}]}
  """

  @narrowed ~S"""
  {"status":"1","info":"OK","infocode":"10000","count":"1",
   "suggestion":{"keywords":[],"cities":[]},"buslines":[
    {"id":"110100010042","type":"地铁线路","name":"地铁1号线(苹果园--四惠东)",
     "citycode":"010","start_stop":"苹果园","end_stop":"四惠东"}]}
  """

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v3/bus/linename", fn request ->
      if Map.has_key?(URI.decode_query(request.query), "city") do
        {200, @narrowed}
      else
        {200, @nationwide}
      end
    end)

    :ok
  end

  doctest Amap.Bus
end
