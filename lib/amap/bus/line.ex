defmodule Amap.Bus.Line do
  @moduledoc """
  A bus line, as the two line endpoints answer with it.

  Scalars keep the wire's form: `type` is a **Chinese word** (`"地铁"`, `"普通公交"`)
  rather than a code, `loop`, `status`, `distance`, `basic_price` and `total_price`
  are strings, and `name` carries the route plus its terminals — `"854路(望京西枢纽站
  --孙河公交场站)"` — exactly as the service writes it.

  `polyline` is decoded by `Amap.Coord.parse_polyline/1`: a list of parts, one part
  when the string carries no `|`. `bounds` is the line's rectangle, decoded by
  `Amap.Coord.parse_locations/1`. `busstops` is what `extensions: :all` adds, each
  stop with its `sequence` on the line.

  Two page notes this field list settles:

    * the page's table gives **`distance` twice**, 全程里程 and 线路长度, at one level.
      One wire key cannot hold two values, so this is one field — the route's length
      in kilometres;
    * `timedesc` is, in the page's own words, 「内容为 JSON 串，需要解码并做内容解析」.
      The string is carried **as sent**, so nothing is lost while its decoded shape
      is undocumented; `Amap.JSON.decode/1` reads it when a caller needs it.
  """

  alias Amap.Bus.Line.Stop

  defstruct [
    :id,
    :type,
    :name,
    :polyline,
    :citycode,
    :start_stop,
    :end_stop,
    :start_time,
    :end_time,
    :uicolor,
    :timedesc,
    :distance,
    :loop,
    :status,
    :direc,
    :company,
    :basic_price,
    :total_price,
    :bounds,
    busstops: []
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          type: String.t() | nil,
          name: String.t() | nil,
          polyline: [[{float(), float()}]] | nil,
          citycode: String.t() | nil,
          start_stop: String.t() | nil,
          end_stop: String.t() | nil,
          start_time: String.t() | nil,
          end_time: String.t() | nil,
          uicolor: String.t() | nil,
          timedesc: String.t() | nil,
          distance: String.t() | nil,
          loop: String.t() | nil,
          status: String.t() | nil,
          direc: String.t() | nil,
          company: String.t() | nil,
          basic_price: String.t() | nil,
          total_price: String.t() | nil,
          bounds: [{float(), float()}] | nil,
          busstops: [Stop.t()]
        }
end
