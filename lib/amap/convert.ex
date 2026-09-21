defmodule Amap.Convert do
  @moduledoc """
  坐标转换 — other coordinate systems into Amap's.

  Amap's own system is what every other endpoint expects, so a track recorded by a
  GPS device has to come through here first.

  `coordsys` says what the input is, and **Amap's default is `autonavi`** — "do not
  convert" — so a call that leaves it out is answered with its own input. This
  module sends the parameter only when the caller chose one, rather than picking a
  conversion nobody asked for.

  Amap converts up to 40 points per call.

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
      iex> {:ok, unconverted} = Amap.Convert.convert(client, [{116.481499, 39.990475}])
      iex> unconverted.locations
      [{116.481499, 39.990475}]
      iex> {:ok, converted} =
      ...>   Amap.Convert.convert(client, [{116.481499, 39.990475}], coordsys: :gps)
      iex> converted.locations
      [{116.487001, 39.992123}]
      iex> Amap.Convert.convert(client, Enum.map(1..41, &{&1 / 10, 39.99}))
      ** (ArgumentError) :locations count must be between 1 and 40, got: 41

  Leaving `:coordsys` out is a call, not a mistake: Amap's own default is
  `autonavi` — "do not convert" — so the first call is answered with its own input,
  and the stand-in reads the point back as sent. The last call is the page's
  40-point ceiling, refused here rather than by Amap.
  """

  alias Amap.Coord
  alias Amap.Param
  alias Amap.Validate

  @path "/v3/assistant/coordinate/convert"
  @max_locations 40
  @coordsys [:gps, :mapbar, :baidu, :autonavi]

  defstruct locations: []

  @type t :: %__MODULE__{locations: [{float(), float()}]}

  @doc """
  Converts coordinates into Amap's system.

  `locations` is a list of 1 to 40 `{lon, lat}` tuples. `:coordsys` is `:gps`,
  `:mapbar`, `:baidu` or `:autonavi`.

  The request's points go out `|`-separated and the answer's come back
  `;`-separated — so `Amap.Param.locations/1`, which joins with `;`, describes the
  answer and **not** this request.
  """
  @spec convert(Amap.Client.t(), [{number(), number()}], keyword()) ::
          {:ok, t()} | {:error, Amap.Error.t()}
  def convert(client, locations, opts \\ []) do
    locations = Validate.points!(locations, ":locations")
    Validate.range!(length(locations), ":locations count", 1, @max_locations)

    params = [
      locations: Param.pipe(Enum.map(locations, &Param.location/1)),
      coordsys: Validate.optional_enum!(Keyword.get(opts, :coordsys), ":coordsys", @coordsys)
    ]

    case Amap.request(client, :restapi, :get, @path, params) do
      {:ok, payload} ->
        {:ok, %__MODULE__{locations: Coord.parse_locations(payload["locations"]) || []}}

      {:error, _} = error ->
        error
    end
  end
end
