defmodule Amap.Falcon.TerminalSearch.Result do
  @moduledoc """
  One terminal as a search endpoint reports it, with its last known position.
  """

  alias Amap.Falcon.TerminalSearch.Location

  defstruct [
    :tid,
    :name,
    :desc,
    :createtime,
    :locatetime,
    :location,
    :props,
    :distance,
    custom: %{}
  ]

  @type t :: %__MODULE__{
          tid: integer() | nil,
          name: String.t() | nil,
          desc: String.t() | nil,
          createtime: integer() | nil,
          locatetime: integer() | nil,
          location: Location.t() | nil,
          props: Amap.JSON.object() | nil,
          distance: number() | nil,
          custom: Amap.JSON.object()
        }
end
