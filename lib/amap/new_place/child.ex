defmodule Amap.NewPlace.Child do
  @moduledoc """
  One sub-POI of a v5 poi, from the `children` group.

  The page lists `sname` (子 poi 分类信息) on the 关键字搜索 table only; the around, polygon
  and detail tables stop at `typecode`, so a call to those three leaves it `nil`.
  """

  defstruct [:id, :name, :location, :address, :subtype, :typecode, :sname]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          location: {float(), float()} | nil,
          address: String.t() | nil,
          subtype: String.t() | nil,
          typecode: String.t() | nil,
          sname: String.t() | nil
        }
end
