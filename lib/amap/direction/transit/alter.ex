defmodule Amap.Direction.Transit.Alter do
  @moduledoc """
  An alternative train Amap offers in place of the one planned — a member of a
  railway's `alters`.

  `name` is the line's own name for the option (备选方案一 — alternative one) and
  `spaces` are its seat classes and fares; see `Amap.Direction.Transit.Space`.

  They arrive only when the call asked for `extensions: :all`.
  """

  alias Amap.Direction.Transit.Space

  defstruct [:id, :name, spaces: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          spaces: [Space.t()]
        }
end
