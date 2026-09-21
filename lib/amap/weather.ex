defmodule Amap.Weather do
  @moduledoc """
  天气查询 — the current conditions in a city, and its three-day forecast.

  One endpoint answers both, and its two `extensions` modes answer **different
  fields** rather than the same fields in more detail, which is why they are two
  functions here: `live/2` for 实况天气 (current conditions) and `forecast/2` for 预报天气
  (the forecast).

  `city` is an **adcode**, not a name — Amap's own `city` parameter on this page
  takes the code, so 北京 (Beijing) is a call-site mistake worth catching before a round
  trip.

  Conditions update several times an hour and forecasts three times a day (around
  08:00, 11:00 and 18:00), so `reporttime` is the field to read rather than
  assuming how fresh the answer is.

  ## Examples

  The examples are doctests: they run against a local stand-in, so they need no key
  and never call Amap. `base_urls` is the override the client documents for exactly
  that — a proxy or a local server — and a real call site omits it:
  `Amap.new(key: …)`. The stand-in's payloads are illustrative, not live readings.

      iex> client =
      ...>   Amap.new(
      ...>     key: "test-key",
      ...>     base_urls: %{restapi: "http://localhost:21617"}
      ...>   )
      iex> {:ok, [live]} = Amap.Weather.live(client, "110000")
      iex> {live.weather, live.reporttime}
      {"晴", "2026-09-17 14:00:00"}
      iex> {:ok, [forecast]} = Amap.Weather.forecast(client, "110000")
      iex> Enum.map(forecast.casts, & &1.date)
      ["2026-09-17", "2026-09-18"]
      iex> Amap.Weather.live(client, "北京")
      ** (ArgumentError) :city must be an adcode such as "110000", got: "北京"

  The two modes answer different fields rather than the same fields in more detail:
  `live/2` carries one set of conditions, `forecast/2` carries days under `casts`.
  And a city name is refused before any request is built — Amap's own `city`
  parameter takes the code.
  """

  alias Amap.Weather.Cast
  alias Amap.Weather.Forecast
  alias Amap.Weather.Live

  @path "/v3/weather/weatherInfo"

  @doc """
  The current conditions in a city.

  `city` is a six-digit adcode such as `"110000"`. Returns the `lives` entries
  Amap sent — usually one.
  """
  @spec live(Amap.Client.t(), String.t()) :: {:ok, [Live.t()]} | {:error, Amap.Error.t()}
  def live(client, city), do: weather(client, city, :base, "lives", &to_live/1)

  @doc """
  Three days of forecast for a city.

  Returns the `forecast` entries Amap sent — again usually one, each holding its
  days in `casts`.
  """
  @spec forecast(Amap.Client.t(), String.t()) ::
          {:ok, [Forecast.t()]} | {:error, Amap.Error.t()}
  def forecast(client, city), do: weather(client, city, :all, "forecast", &to_forecast/1)

  defp weather(client, city, extensions, key, mapper) do
    params = [city: validate_city!(city), extensions: Atom.to_string(extensions)]

    case Amap.request(client, :restapi, :get, @path, params) do
      {:ok, payload} -> {:ok, Enum.map(payload[key] || [], mapper)}
      {:error, _} = error -> error
    end
  end

  defp validate_city!(city) when is_binary(city) do
    if Regex.match?(~r/^\d+$/, city) do
      city
    else
      raise ArgumentError, city_message(city)
    end
  end

  defp validate_city!(other), do: raise(ArgumentError, city_message(other))

  defp city_message(value),
    do: ":city must be an adcode such as \"110000\", got: #{inspect(value)}"

  defp to_live(payload) do
    %Live{
      province: payload["province"],
      city: payload["city"],
      adcode: payload["adcode"],
      weather: payload["weather"],
      temperature: payload["temperature"],
      winddirection: payload["winddirection"],
      windpower: payload["windpower"],
      humidity: payload["humidity"],
      reporttime: payload["reporttime"]
    }
  end

  defp to_forecast(payload) do
    %Forecast{
      city: payload["city"],
      adcode: payload["adcode"],
      province: payload["province"],
      reporttime: payload["reporttime"],
      casts: Enum.map(payload["casts"] || [], &to_cast/1)
    }
  end

  defp to_cast(payload) do
    %Cast{
      date: payload["date"],
      week: payload["week"],
      dayweather: payload["dayweather"],
      nightweather: payload["nightweather"],
      daytemp: payload["daytemp"],
      nighttemp: payload["nighttemp"],
      daywind: payload["daywind"],
      nightwind: payload["nightwind"],
      daypower: payload["daypower"],
      nightpower: payload["nightpower"]
    }
  end
end
