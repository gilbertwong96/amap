defmodule Amap.Geocoding.StreetNumber do
  @moduledoc """
  The house number a point resolves to.

  `location` is the `{lon, lat}` Amap has for that number, `direction` is the side
  of the street it is on, and `distance` — a string, like Amap sends it — is how
  far it is from the coordinate that was asked about.
  """

  defstruct [:street, :number, :location, :direction, :distance]

  @type t :: %__MODULE__{
          street: String.t() | nil,
          number: String.t() | nil,
          location: {float(), float()} | nil,
          direction: String.t() | nil,
          distance: String.t() | nil
        }
end
