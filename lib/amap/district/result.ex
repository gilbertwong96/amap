defmodule Amap.District.Result do
  @moduledoc """
  What a district query answered: the divisions, and Amap's guess when there are
  none.

  `items` is a list because a keyword can match more than one division; each entry
  carries its own children in its `districts` field, the same struct at every
  level.
  """

  alias Amap.District
  alias Amap.District.Suggestion

  defstruct items: [], suggestion: nil

  @type t :: %__MODULE__{
          items: [District.t()],
          suggestion: Suggestion.t() | nil
        }
end
