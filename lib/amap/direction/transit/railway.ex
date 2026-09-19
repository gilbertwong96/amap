defmodule Amap.Direction.Transit.Railway do
  @moduledoc """
  The train a leg rides — a segment's `railway`.

  `name` is the line (京沪线), `trip` the service number (G101), and `type` Amap's
  线路类型 code, which stays a string:

  | code | 车次 |
  |---|---|
  | 2010 | 普客火车 |
  | 2011 | G 字头的高铁火车 |
  | 2012 | D 字头的动车火车 |
  | 2013 | C 字头的城际火车 |
  | 2014 | Z 字头的直达特快火车 |
  | 2015 | T 字头的特快火车 |
  | 2016 | K 字头的快车火车 |
  | 2017 | L 字头、Y 字头的临时火车 |
  | 2018 | S 字头的郊区线火车 |

  `time` is how long the ride takes (seconds) and `distance` how far it goes
  (metres) — both strings, like every other scalar here.

  `departure_stop`, `arrival_stop` and `via_stop` are `Amap.Direction.Transit.Stop`
  structs, and **a train's stops carry the fields a bus stop does not** — the
  district code, the times, whether it is a terminus. `via_stop` and `alters` appear
  only when the call asked for `extensions: :all`.

  `alters` are the alternatives Amap aggregates beside this train; each names itself
  and lists its seat classes.
  """

  alias Amap.Direction.Transit.Alter
  alias Amap.Direction.Transit.Stop

  defstruct [
    :id,
    :time,
    :name,
    :trip,
    :distance,
    :type,
    :departure_stop,
    :arrival_stop,
    via_stop: [],
    alters: []
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          time: String.t() | nil,
          name: String.t() | nil,
          trip: String.t() | nil,
          distance: String.t() | nil,
          type: String.t() | nil,
          departure_stop: Stop.t() | nil,
          arrival_stop: Stop.t() | nil,
          via_stop: [Stop.t()],
          alters: [Alter.t()]
        }
end
