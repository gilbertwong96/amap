defmodule Amap.Direction.Distance do
  @moduledoc """
  How far one origin is from the destination — a member of `/v3/distance`'s results.

  `origin_id` and `dest_id` are **1-based sequence numbers** saying which origin this
  answers, in the order the caller sent them, and they stay the strings Amap writes
  (`"1"`, not `1`).

  `info` and `code` are how Amap reports failure **per item**: both are absent on a
  result it could measure, and appear on the ones it could not — `code` distinguishes
  no **drivable** road between the two points (`"1"` — the page's 可行车, which only
  rules out roads a car can use), an origin or destination too far from every road
  (`"2"`) and a point outside China (`"3"`). The call itself is still `{:ok, _}`,
  which is why the pair lives here instead of in `Amap.Error`: across a hundred origins
  one failure is data, and a caller that only checked the tuple would miss it.

  `distance` is metres and `duration` seconds, both strings like every other scalar
  here.
  """

  defstruct [:origin_id, :dest_id, :distance, :duration, :info, :code]

  @type t :: %__MODULE__{
          origin_id: String.t() | nil,
          dest_id: String.t() | nil,
          distance: String.t() | nil,
          duration: String.t() | nil,
          info: String.t() | nil,
          code: String.t() | nil
        }
end
