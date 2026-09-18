defmodule Amap.WeatherTest do
  use ExUnit.Case, async: true

  alias Amap.TestServer
  alias Amap.Weather
  alias Amap.Weather.Cast
  alias Amap.Weather.Forecast
  alias Amap.Weather.Live

  @lives ~s({"status":"1","info":"OK","infocode":"10000","count":"1","lives":[) <>
           ~s({"province":"北京市","city":"北京市","adcode":"110000","weather":"晴",) <>
           ~s("temperature":"24","winddirection":"西北","windpower":"≤3","humidity":"40",) <>
           ~s("reporttime":"2026-09-17 14:00:00"}]})

  @forecasts ~s({"status":"1","info":"OK","infocode":"10000","count":"1","forecast":[) <>
               ~s({"city":"北京市","adcode":"110000","province":"北京市",) <>
               ~s("reporttime":"2026-09-17 11:00:00","casts":[) <>
               ~s({"date":"2026-09-17","week":"4","dayweather":"晴","nightweather":"多云",) <>
               ~s("daytemp":"28","nighttemp":"16","daywind":"西北","nightwind":"北",) <>
               ~s("daypower":"1-3","nightpower":"1-3"},) <>
               ~s({"date":"2026-09-18","week":"5","dayweather":"多云","nightweather":"阴",) <>
               ~s("daytemp":"26","nighttemp":"15","daywind":"北","nightwind":"东北",) <>
               ~s("daypower":"1-3","nightpower":"1-3"}]}]})

  setup do
    server = TestServer.start!()

    client =
      Amap.new(
        key: "test-key",
        base_urls: %{
          restapi: "http://localhost:#{server.port}",
          tsapi: "http://localhost:#{server.port}"
        }
      )

    {:ok, server: server, client: client}
  end

  test "live/2 asks for the real-time mode", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/weather/weatherInfo", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @lives}
    end)

    assert {:ok, [%Live{}]} = Weather.live(client, "110000")

    assert_receive {:query, query}
    assert query["city"] == "110000"
    assert query["extensions"] == "base"
  end

  test "forecast/2 asks for the forecast mode", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/weather/weatherInfo", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @forecasts}
    end)

    assert {:ok, [%Forecast{}]} = Weather.forecast(client, "110000")

    assert_receive {:query, query}
    assert query["city"] == "110000"
    assert query["extensions"] == "all"
  end

  test "maps the current conditions, keeping the strings Amap sends", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v3/weather/weatherInfo", fn _req -> {200, @lives} end)

    assert {:ok, [live]} = Weather.live(client, "110000")
    assert live.province == "北京市"
    assert live.city == "北京市"
    assert live.adcode == "110000"
    assert live.weather == "晴"
    assert live.temperature == "24"
    assert live.winddirection == "西北"
    assert live.windpower == "≤3"
    assert live.humidity == "40"
    assert live.reporttime == "2026-09-17 14:00:00"
  end

  test "maps a forecast and every day in it", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/weather/weatherInfo", fn _req ->
      {200, @forecasts}
    end)

    assert {:ok, [forecast]} = Weather.forecast(client, "110000")
    assert forecast.city == "北京市"
    assert forecast.adcode == "110000"
    assert forecast.province == "北京市"
    assert forecast.reporttime == "2026-09-17 11:00:00"

    assert [%Cast{} = today, %Cast{} = tomorrow] = forecast.casts
    assert today.date == "2026-09-17"
    assert today.dayweather == "晴"
    assert today.nightweather == "多云"
    assert today.daytemp == "28"
    assert today.nighttemp == "16"
    assert today.daypower == "1-3"

    assert tomorrow.date == "2026-09-18"
    assert tomorrow.nightwind == "东北"
    assert tomorrow.nighttemp == "15"
  end

  test "answers with an empty list when Amap has nothing", %{server: server, client: client} do
    empty = ~s({"status":"1","info":"OK","infocode":"10000","count":"0","lives":[]})

    TestServer.expect_once(server, "GET", "/v3/weather/weatherInfo", fn _req -> {200, empty} end)

    assert Weather.live(client, "110000") == {:ok, []}
  end

  test "rejects a city name, which this endpoint does not take", %{client: client} do
    assert_raise ArgumentError, ~r/:city must be an adcode such as "110000", got: "北京"/, fn ->
      Weather.live(client, "北京")
    end

    assert_raise ArgumentError, ~r/:city must be an adcode/, fn ->
      Weather.forecast(client, 110_000)
    end
  end

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    refusal = ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

    TestServer.expect_once(server, "GET", "/v3/weather/weatherInfo", fn _req -> {200, refusal} end)

    assert {:error, %Amap.Error{}} = Weather.live(client, "110000")
  end
end
