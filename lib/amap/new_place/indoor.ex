defmodule Amap.NewPlace.Indoor do
  @moduledoc """
  A v5 poi's 室内相关信息 (`indoor`), returned only when `show_fields` asks for it.

  `indoor_map` is `"1"` when the POI has indoor data and `"0"` when it has none; the page
  says `cpid`, `floor` and `truefloor` are not returned when it is `"0"`, so on that answer
  they are `nil` and `indoor_map` is the field that says why.
  """

  defstruct [:indoor_map, :cpid, :floor, :truefloor]

  @type t :: %__MODULE__{
          indoor_map: String.t() | nil,
          cpid: String.t() | nil,
          floor: String.t() | nil,
          truefloor: String.t() | nil
        }
end
