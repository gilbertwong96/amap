defmodule Amap.Bus.Stops do
  @moduledoc """
  What a station query answered: the stops, Amap's count, and its suggestion.

  `count` is the size of the whole result set rather than of this page, and it
  stays the **string** Amap sent — every number in this family is a string. The
  station pages' response trees list neither `count` nor `suggestion`; the wire
  sent `count` on both station endpoints and `suggestion` on the keyword search.

  `suggestion` is `nil` for the id lookup, which sent none (its page tree does not
  list one either).
  """

  alias Amap.Bus.Stop
  alias Amap.Bus.Suggestion

  defstruct [:count, :suggestion, busstops: []]

  @type t :: %__MODULE__{
          count: String.t() | nil,
          suggestion: Suggestion.t() | nil,
          busstops: [Stop.t()]
        }
end
