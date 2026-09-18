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
    locations = validate_locations!(locations)

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

  defp validate_locations!(locations) when is_list(locations) do
    if locations == [] do
      raise ArgumentError, ":locations must not be empty"
    end

    unless Enum.all?(locations, &point?/1) do
      raise ArgumentError, locations_message(locations)
    end

    Validate.range!(length(locations), ":locations count", 1, @max_locations)
    locations
  end

  defp validate_locations!(other), do: raise(ArgumentError, locations_message(other))

  defp point?({lon, lat}) when is_number(lon) and is_number(lat), do: true
  defp point?(_other), do: false

  defp locations_message(value),
    do: ":locations must be a list of {lon, lat} tuples, got: #{inspect(value)}"
end
