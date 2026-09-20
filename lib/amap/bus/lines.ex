defmodule Amap.Bus.Lines do
  @moduledoc """
  What a line query answered: the lines, Amap's count, and its suggestion.

  `count` is the size of the whole result set rather than of this page, and it
  stays the **string** Amap sent — `lineid`'s response table is the only one of the
  page's four that lists it, while the wire sent it on every probed endpoint.
  `suggestion` is `nil` for the id lookup, which the page does not list; the live
  run read `lineid` itself, but its `suggestion` is the one field no probe has
  observed — the struct carries it all the same.
  """

  alias Amap.Bus.Line
  alias Amap.Bus.Suggestion

  defstruct [:count, :suggestion, buslines: []]

  @type t :: %__MODULE__{
          count: String.t() | nil,
          suggestion: Suggestion.t() | nil,
          buslines: [Line.t()]
        }
end
