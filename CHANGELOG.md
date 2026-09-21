# Changelog

Notable changes to this project, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Amap.new/1` and `%Amap.Client{}`, with defaults that may come from
  application config, and validation that names the option it rejected.
- One `Amap.request/6` entry point for both API families, `restapi` and `tsapi`,
  collapsing either response envelope into a bare payload map so callers never
  branch on the family.
- Amap parameter encoding, plus digital signatures when `private_key:` is set.
- `%Amap.Error{}` and the family-aware Amap reason table, so callers branch on
  `reason` and never on a numeric code.
- Opt-in token-bucket rate limiting via `limiter: :personal | :enterprise | [rate: …]`.
- Telemetry spans for requests and for time spent waiting on the limiter.
- Retry driven by the failure's own classification, off by default.
- Falcon track service as module functions: `Amap.Falcon.Service` and
  `Amap.Falcon.Terminal` for the resources themselves, `Amap.Falcon.TerminalSearch`
  for the four search shapes, and `Amap.Falcon.TerminalMonitor` for a terminal's
  last known position. Coordinates are `{longitude, latitude}` everywhere; the
  endpoints that want latitude first are handled internally.
- `Amap.Param.lat_lng/1` and `Amap.Param.polygon/1` for the wire formats those
  endpoints take, and `Amap.Validate` for the rules Amap documents about names and
  ranges, enforced before a request is built rather than by a round trip.
- The Web service queries: `Amap.IpLocation.ip/2`, `Amap.Geocoding.geo/3` and
  `regeo/3`, `Amap.Convert.convert/3`, `Amap.District.district/2`,
  `Amap.Weather.live/2` and `Amap.Weather.forecast/2`, and `Amap.Traffic.road/4`,
  `circle/4` and `rectangle/4`. `Amap.Traffic` is a 高级服务 interface, opened by
  Amap per account, so a key may be refused there while every other call works.
- `Amap.Coord`, which parses the coordinate strings payloads carry — `;` between
  points, `|` between the parts of a boundary — so composite fields reach a caller
  as `{lon, lat}` tuples.
- `Amap.Validate.point!/2`, `points!/2` and `optional_enum!/3`, for the coordinate
  pairs and the `base`/`all` and coordinate-system parameters three endpoints share.
- Route planning on both generations: `Amap.Direction` covers v3's `driving/4`,
  `walking/4`, `transit/5` and the measuring `distance/4` plus the v4 `bicycling/4`,
  and `Amap.NewRoute` covers v5's `driving/4`, `walking/4`, `bicycling/4`,
  `electrobike/4` and `transit/5`. `Amap.Direction.bicycling/4` answers the Falcon
  envelope from the Web service host, which is why a call names both axes:
  `Amap.request/6` takes the host as `:restapi` and `envelope: :tsapi`.
- `Amap.NewRoute`'s optional groups arrive only when `show_fields` names them, and
  `walk_type` arrives inside each step's `navi` rather than on the step where the
  walking and riding pages list it as a group of its own — as the live probe on
  `/v5/direction/walking` showed; `bicycling/4` and `electrobike/4` share that
  mapper and page but were not probed.
- v5's `driving/4` takes `method: :post` for parameters a URL cannot carry: with the
  documented maxima, 16 waypoints and 32 avoid-polygons, the query measured 12,129
  bytes, which GET answered with `:unexpected_response` and POST answered with the
  route.
- `Amap.Direction.driving/4` gains `roadaggregation: true`, which replaces a path's
  `steps` with `roads` — the page words it as adding a grouping above them, and the
  live run saw the replacement — each entry an `Amap.Direction.Road` whose fields
  are the four keys the wire printed.
- 公交信息查询 as `Amap.Bus`: `stopid/3`, `stopname/3`, `lineid/3` and `linename/3`,
  with both nesting shapes — a station's lines as `Amap.Bus.Stop.Busline`, a line's
  stops as `Amap.Bus.Line.Stop`. `count` stays the string Amap sends, the keyword
  searches carry Amap's `suggestion` as `Amap.Bus.Suggestion`, and `linename`'s
  documented 全国 default is real: omitting `city` searches the whole country,
  which a probe confirmed. The page lists `lineid`'s `distance` twice at one level,
  so it maps to one field and the duplicate row is recorded as a page defect.
- Place search on both generations, plus 输入提示: `Amap.Place` covers v3's
  `/v3/place/{text,around,polygon,detail}` and `Amap.NewPlace` v5's
  `/v5/place/{text,around,polygon,detail}`, sharing `Amap.Search`; `Amap.InputTips`
  covers `/v3/assistant/inputtips`. Paging is `offset` (1..25, the page's own strong
  advice) and `page` (1..200) on v3 against `page_size` (1..25) and `page_num`
  (1..200) on v5 — both pages answer at most 200 rows for one set of parameters,
  which is what the page bound encodes. `region` adds search weight where
  `city_limit` makes it strict, `show_fields` must name the v5 groups a caller wants,
  and detail takes one id on v3 against up to ten on v5. `/v5/aoi/polyline` is
  recorded as needing a 工单 and is not implemented.
- The two search generations keep their pages' field depths: v3 leaves
  `parking_type`, `alias`, `rating` and `cost` flat beside `biz_ext`, v5 nests them
  under `business` and `indoor`. The v5 groups whose page cannot say whether they are
  a list or one object (`children`, `photos`) are typed as a union: the live run has only
  shown lists, and the object branch stays because the page draws one and no run has sent it.

- 轨迹纠偏 as `Amap.Grasproad.driving/2`: a driven track of up to 500 points — each
  `%{location: {lon, lat}, ag, tm, sp}`, with `tm` in seconds, the first point's from
  1970 and the rest as differences from it — sent as a **JSON array**. It is the tree's
  second JSON-body endpoint, which is why `Amap.Request` now accepts a non-empty list
  of maps as a JSON body while still refusing every other JSON value. A single point
  map and a list of them are both accepted, and both go out as the array the page
  requires. The answer is the Falcon envelope from the Web service host, so the call
  names host `:restapi` and envelope `:tsapi`, and `30001` 抓路失败 maps
  to `:grasproad_failed` with `retry: :no`. A live run (2026-09-21) confirmed the page's
  untyped shapes: success is `errcode: 0`, `distance` and each `points[]` `x`/`y` arrive
  as JSON numbers (floats) rather than the v3/v5 routes' strings, and Amap **densifies**
  the corrected track — 8 sent points came back as 28. It also answered `30001` with the
  generic `ENGINE_RESPONSE_DATA_ERROR`/引擎返回数据异常 for a raw empty array, a one-point
  track and a sparse one, and a raw 501-object body with `20000`/`INVALID_PARAMS` and a
  500-specific message, which is Amap's own side of the SDK's 1..500 bound.
- `Amap.Host`, one table stating per host its base URL, the envelopes it answers,
  the auth each envelope uses, and the name it gives the account key. The request
  path reads it instead of inferring the envelope and the signature from one family
  flag. It also describes the two hosts the SDK cannot call yet:
  `et-api.amap.com` (`code`/`msg` envelope, `clientKey` + `timestamp` + `digest`,
  whose algorithm Amap does not publish) and `apilocate.amap.com` (`status`/`info`
  around `result`, with **no `infocode` row** and symbolic `info` values). A request
  that would need the unobtainable digest raises rather than sending; the
  `apilocate` envelope is parsed, though no endpoint module exists for it.
- `mix integration`, which runs the `:integration`-tagged live checks (`--only
  integration`) and refuses to start when `AMAP_KEY` is unset, so a skipped run
  cannot read as a pass.
- `Amap.IpLocation`'s moduledoc examples, executed as doctests against the local test
  server, and the convention the rest of the sweep follows.
- `mix docs` includes `README.md` and `CHANGELOG.md` as ExDoc extras, so the generated
  doc set carries both alongside the module pages.

### Changed

- `Amap.Response` applies Amap's empty-array convention to the flat envelope too, so
  a field Amap has no value for reaches a caller as `nil` rather than as `[]`.
- `Amap.Falcon.Validate` became `Amap.Validate`, with only the track service's name
  rules left family-specific, and `Amap.Falcon.Point`'s `parse_location/1` moved to
  `Amap.Coord.parse_location/1`.
- `Amap.Falcon.TerminalMonitor.Position` and `Amap.Falcon.Grasproad.Point` described
  one wire object twice, so both are now `Amap.Falcon.Position`.
- Trajectories: `Amap.Falcon.Trace` creates and deletes one, and
  `Amap.Falcon.Point` uploads its points in batches of up to 100. A batch Amap
  only partly accepts is still a successful call, whose `errorpoints` list says
  which points to send again.
- `Amap.Falcon.Grasproad` reads trajectories back with `trsearch/4` — by trace, or
  by a window of at most 24 hours — with Amap's denoise and snap options given as
  a keyword list rather than as its own mini-format. `roaddata/2` asks which roads
  a trajectory ran on, which Amap enables by ticket.
- `Amap.Falcon.TerminalColumn` and `Amap.Falcon.TraceColumn` declare the custom
  fields that `props` needs. Amap rejects an undeclared field, so these are what
  make `props` usable at all.
- Geofences in four shapes — `Amap.Falcon.Geofence.add_circle/4`, `add_polygon/4`,
  `add_polyline/4` and `add_district/4`, each with a matching `update_*` — plus
  `delete/3` and `list/2`. Fence coordinates are longitude-first.
- `Amap.Falcon.FenceTerminal` binds and unbinds the terminals a fence watches, and
  `Amap.Falcon.FenceStatus` answers whether a terminal or a coordinate is inside a
  fence. An id list longer than Amap's 100-per-call limit raises rather than being
  truncated silently.
- `Amap.Falcon.TrackAnalysis` reads a trace's driving behaviour — harsh
  acceleration, braking, steering and speeding, each as a list of points — and its
  stay points.
- `Amap.Falcon.TrackMatch` compares how much two trajectories overlap. It is the
  one Amap endpoint that takes a JSON body, so `Amap.request/6` grew a
  `body: :form | :json` option rather than a second pipeline.
- **Breaking:** `Amap.request/6`'s second argument names the host, and
  `opts[:envelope]` names the response envelope when the endpoint's is not the
  host's default. The `host:` option is gone, and the family no longer decides the
  URL, the signature or the account key's name — `Amap.Host` does.
  `/v4/direction/bicycling` is now
  `Amap.request(client, :restapi, :get, path, params, envelope: :tsapi)`, and
  `/v4/grasproad/driving` the same with `:post`; passing the removed `:host:` (or any
  other option the call does not take) raises `ArgumentError` instead of being
  ignored, so a call site left over from the old shape fails loudly rather than going
  to the positional host. Telemetry's start metadata carries `host:` where it carried
  `family:`.
- `%Amap.Error{}` carries the request that produced it in every case: `Amap.request/6`
  attaches `%{method:, path:, params:}` to an envelope refusal, a body that did not parse,
  and a limiter timeout too, not only to transport and HTTP-status failures.
- **Not included in this release:** toll estimation (`Amap.Falcon.Etc`), which Amap
  opens only to enterprise developers. It is deferred rather than guessed at until an
  account exists for it.

### Notes

- **`key` and `sig` are reserved request parameters.** `Amap.request/5` raises
  `ArgumentError` when `params` supplies either, because the client injects both.
  Passing them used to put a second `key` on the wire, where the caller's value
  silently won and the signature then covered a string the server did not read.
- A bucket is per node: N nodes sharing one key multiply the effective QPS by N.
  `Amap.Limiter` is not a behaviour yet, so multi-node deployments need an
  external limiter. Extracting `acquire/2` behind a behaviour is a mechanical
  change, since the request pipeline is the only caller.
- `Amap.Param` rounds coordinates to six decimal places (~0.1m), which is Amap's
  documented precision and keeps signature strings stable across platforms.
