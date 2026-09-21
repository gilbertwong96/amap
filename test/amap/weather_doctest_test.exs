defmodule Amap.WeatherDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # The two `extensions` modes answer different keys: `lives` for base, `forecast`
  # for all.
  @lives ~s({"status":"1","info":"OK","infocode":"10000","count":"1","lives":[) <>
           ~s({"province":"北京市","city":"北京市","adcode":"110000","weather":"晴",) <>
           ~s("temperature":"24","reporttime":"2026-09-17 14:00:00"}]})

  @forecasts ~s({"status":"1","info":"OK","infocode":"10000","count":"1","forecast":[) <>
               ~s({"city":"北京市","adcode":"110000","province":"北京市",) <>
               ~s("reporttime":"2026-09-17 11:00:00","casts":[) <>
               ~s({"date":"2026-09-17","dayweather":"晴","nightweather":"多云",) <>
               ~s("daytemp":"28","nighttemp":"16"},) <>
               ~s({"date":"2026-09-18","dayweather":"多云","nightweather":"阴",) <>
               ~s("daytemp":"26","nighttemp":"15"}]}]})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v3/weather/weatherInfo", fn request ->
      if URI.decode_query(request.query)["extensions"] == "all" do
        {200, @forecasts}
      else
        {200, @lives}
      end
    end)

    :ok
  end

  doctest Amap.Weather
end
