defmodule Amap.Geocoding.Road do
  @moduledoc """
  A road near the point, with how far away it is.
  """

  defstruct [:id, :name, :distance, :direction, :location]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          distance: String.t() | nil,
          direction: String.t() | nil,
          location: {float(), float()} | nil
        }
end
