defmodule Amap.NewPlace.Poi do
  @moduledoc """
  One POI from a v5 搜索POI 2.0 answer.

  The base fields are the page's; everything after `atag` is a `show_fields` group and is
  `nil` when the call did not ask for it. A group's shape is the one thing the 2.0 page
  cannot say — it prints every group as an `object` whose fields follow, for single objects
  and lists alike — so the two collection-shaped groups (`children`, `photos`) keep the
  union type: the run has only shown lists (`children` a list of 1, `photos` a list of 3),
  and the object branch stays because the page draws every group as one and no run has sent
  one. The mappers keep whichever shape arrived rather than guessing one. `business`,
  `indoor` and `navi` are documented as single objects and read that way.

  `atag` is detail's own field (现状仅ID查询返回 on the v3 page; the 2.0 detail table lists
  it while the other three do not), so a search answer leaves it `nil`.

  The v3 POI keeps `parking_type`, `alias`, `indoor_map`, `rating` and `cost` flat and
  carries the ordering flags in `biz_ext`; here they live in `business` and `indoor`. That
  depth difference is why the two generations have two structs.
  """

  alias Amap.NewPlace.Business
  alias Amap.NewPlace.Child
  alias Amap.NewPlace.Indoor
  alias Amap.NewPlace.Navi
  alias Amap.NewPlace.Photo

  defstruct [
    :name,
    :id,
    :parent,
    :distance,
    :location,
    :type,
    :typecode,
    :pname,
    :cityname,
    :adname,
    :address,
    :pcode,
    :adcode,
    :citycode,
    :atag,
    :children,
    :business,
    :indoor,
    :navi,
    :photos
  ]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          id: String.t() | nil,
          parent: String.t() | nil,
          distance: String.t() | nil,
          location: {float(), float()} | nil,
          type: String.t() | nil,
          typecode: String.t() | nil,
          pname: String.t() | nil,
          cityname: String.t() | nil,
          adname: String.t() | nil,
          address: String.t() | nil,
          pcode: String.t() | nil,
          adcode: String.t() | nil,
          citycode: String.t() | nil,
          atag: String.t() | nil,
          children: [Child.t()] | Child.t() | nil,
          business: Business.t() | nil,
          indoor: Indoor.t() | nil,
          navi: Navi.t() | nil,
          photos: [Photo.t()] | Photo.t() | nil
        }
end
