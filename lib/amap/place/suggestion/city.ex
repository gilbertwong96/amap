defmodule Amap.Place.Suggestion.City do
  @moduledoc """
  One city in a v3 search's suggestion list: its name, and how many of the keyword's
  results are inside it (`num`, which stays the string Amap sent).
  """

  defstruct [:name, :num, :citycode, :adcode]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          num: String.t() | nil,
          citycode: String.t() | nil,
          adcode: String.t() | nil
        }
end
