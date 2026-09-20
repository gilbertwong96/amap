defmodule Amap.InputTips.Tip do
  @moduledoc """
  One suggestion from `/v3/assistant/inputtips`.

  `id` is what matched: a POI id, a bus id or a busline id, depending on the `datatype`
  the call asked for. `location` is absent (`nil`) on a busline tip — the page says 当搜索
  数据为 busline 类型时，此字段不返回 — and `district` is the province plus city plus
  district, or the city plus district for a 直辖市 (municipality directly under the central
  government).
  """

  defstruct [:id, :name, :district, :adcode, :location, :address]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          district: String.t() | nil,
          adcode: String.t() | nil,
          location: {float(), float()} | nil,
          address: String.t() | nil
        }
end
