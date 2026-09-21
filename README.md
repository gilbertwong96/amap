# Amap

Elixir client for the [Amap](https://lbs.amap.com) (高德地图) Web APIs: the Web
service API (`restapi.amap.com`) and the Falcon track service
(`tsapi.amap.com`).

## Requirements

- Elixir `~> 1.18` — the floor comes from Elixir's built-in `JSON` module, which
  arrived in 1.18.
- **Erlang/OTP 27 or later.** This is the supported and tested range: CI covers
  OTP 27 and 28. Earlier releases are untested rather than known-broken.
- TLS trust comes from the OS trust store rather than a bundled `castore`,
  because `castore` is only an optional dependency of Mint. A deployment image
  without CA certificates therefore fails TLS with an opaque error rather than
  naming the cause.

## Status

The Web service API and the Falcon track service are both implemented, in the
modules the sections below name; `Amap.request/6` is the stable entry point they
build on.

## Installation

```elixir
def deps do
  [{:amap, "~> 0.1.0"}]
end
```

## Usage

```elixir
client = Amap.new(key: System.fetch_env!("AMAP_KEY"))

{:ok, %{"province" => province}} =
  Amap.request(client, :restapi, :get, "/v3/ip", %{})
```

The second argument names the host — `Amap.Host.names()` — and `envelope:`
names the response envelope when the endpoint's is not that host's default,
as the `/v4/` generation on `restapi.amap.com` is not: it answers the Falcon
envelope, so those calls pass `envelope: :tsapi`. `Amap.Host` is also where a
host's base URL, signing and account-key name are stated.

The key can live in config instead of at every call site:

```elixir
config :amap, :key, System.fetch_env!("AMAP_KEY")
```

### Errors

Amap returns HTTP 200 even when the body reports a failure, so the SDK never
uses the HTTP status to decide success. Failures come back as
`{:error, %Amap.Error{}}`.

**Branch on `error.reason`, never on `error.code`.** The two API families have
overlapping but different code tables, and a handful of numbers mean different
things in each.

### Signing

Set `private_key:` to enable Amap's digital signature. Signing is part of the
host's description in `Amap.Host`: the flat envelope on `restapi.amap.com` is
signed, the Falcon envelope is not, and neither is the `/v4/` generation on the
Web service host — the Falcon documentation and those pages do not describe
signatures.

```elixir
Amap.new(key: key, private_key: private_key)
```

### Rate limiting

Off by default. Amap's quotas depend on your account type and on which service
you call, so the SDK does not guess. Enable it explicitly:

```elixir
Amap.new(key: key, limiter: :personal)      # 30 QPS, individual developer
Amap.new(key: key, limiter: :enterprise)    # 50 QPS, enterprise
Amap.new(key: key, limiter: [rate: 5, burst: 5])
```

`acquire/2` waits rather than rejecting, so calls are paced instead of failing.
A bucket is per node: running several nodes with one key multiplies the
effective request rate. The published figures also change, so prefer explicit
values when the exact number matters.

### Retry

Off by default, and when enabled it is driven by the failure rather than by a
blanket policy: a reason classified as a configuration or parameter error is
never retried, however high `:max` is set, because retrying a bad key only
spends quota.

```elixir
Amap.new(key: key, retry: [max: 2, base_delay: 100])
```

A `:backoff` retry sleeps in the **calling** process, so one call can block it
for up to `:max` × the window Amap documents. With `max: 2` and the single
window Amap states (60 seconds, for `ACCESS_TOO_FREQUENT`) that is on the order
of two minutes. There is no total-deadline option; lower `:max` to bound it.

## Falcon track service

Falcon is Amap's track service, on its own host and its own envelope. It is reached
through module functions rather than API paths, so no caller needs to know a wire
format:

```elixir
{:ok, service} = Amap.Falcon.Service.add(client, "fleet-a", desc: "fleet")

{:ok, terminal} =
  Amap.Falcon.Terminal.add(client, service.sid, "truck-01", props: %{"plate" => "AB1234"})

{:ok, page} = Amap.Falcon.TerminalSearch.search(client, service.sid, "truck")
page.count           # matches in total
hd(page.items).name  # "truck-01"

{:ok, position} = Amap.Falcon.TerminalMonitor.lastpoint(client, service.sid, terminal.tid)
position.location    # {114.158, 22.279}
```

Coordinates are always `{longitude, latitude}` tuples, here and everywhere else in
this SDK. The endpoints that want the opposite order on the wire — the search
endpoints' centre and polygon — handle the reversal internally.

Search takes filters and sorting as Elixir terms rather than Amap's `&&`, `|` and
`field:asc` syntax:

```elixir
Amap.Falcon.TerminalSearch.aroundsearch(client, sid, {114.158, 22.279},
  radius: 1000,
  filter: [name: ["truck-01", "truck-02"], lastloctime: {:>=, 1_469_817_532}],
  sort: {:lastloctime, :desc}
)
```

Every function returns `{:ok, struct} | {:error, %Amap.Error{}}`, and `{:ok, nil}`
for a response Amap sends without data. Caller mistakes — a name that breaks
Amap's character rules, a radius out of range, a filter that cannot be encoded —
raise `ArgumentError` before any request is built.

### Trajectories

A `props` field, on a terminal or on a trace, is only legal once it has been
declared — Amap rejects an undeclared one — and a service holds five of each:

```elixir
{:ok, nil} = Amap.Falcon.TerminalColumn.add(client, sid, "plate", :string)
{:ok, nil} = Amap.Falcon.TraceColumn.add(client, sid, "driver", :string)

{:ok, terminal} = Amap.Falcon.Terminal.add(client, sid, "truck-01", props: %{"plate" => "AB1234"})
{:ok, trace} = Amap.Falcon.Trace.add(client, sid, terminal.tid, trname: "morning")

{:ok, upload} =
  Amap.Falcon.Point.upload(client, sid, terminal.tid, trace.trid, [
    %{location: {114.158, 22.279}, locatetime: ~U[2026-09-17 12:00:00Z]},
    %{location: {114.1583, 22.2793}, locatetime: ~U[2026-09-17 12:00:01Z], speed: 40.0}
  ])

upload.errorpoints
# [] when every point was stored. Amap keeps the valid ones in a batch it only
# partly accepts, and this list says which to send again.

{:ok, found} =
  Amap.Falcon.Grasproad.trsearch(client, sid, terminal.tid,
    trid: trace.trid,
    correction: [mapmatch: true, threshold: 20]
  )

found.tracks |> hd() |> Map.get(:points) |> hd()
# %Amap.Falcon.Position{location: {114.158, 22.279}, ...}
```

`trsearch/4` also takes a `:starttime`/`:endtime` window of at most 24 hours
instead of a `trid`. `Amap.Falcon.Grasproad.roaddata/2` answers which roads a
trajectory ran on, but **Amap enables that service by ticket**.

### Geofences

Fences come in four shapes, each with its own create and update call, and a service
holds 1000 of them:

```elixir
{:ok, fence} =
  Amap.Falcon.Geofence.add_circle(client, sid, "warehouse",
    center: {114.158, 22.279},
    radius: 500
  )

# A fence only reports on terminals bound to it.
{:ok, _} = Amap.Falcon.FenceTerminal.bind(client, sid, fence.gfid, [terminal.tid])

{:ok, page} = Amap.Falcon.FenceStatus.location(client, sid, {114.158, 22.279})
hd(page.items).in    # true

Amap.Falcon.Geofence.delete(client, sid, :all)   # or up to 100 ids
```

`add_polygon/4`, `add_polyline/4` and `add_district/4` take a ring of `{lon, lat}`
tuples, a route with a `bufferradius`, or an `adcode`. Coordinates here are
longitude first — what `Amap.Param.locations/1` produces, and *not* the
latitude-first order the terminal-search centre takes.

### Analysis

```elixir
{:ok, behaviour} = Amap.Falcon.TrackAnalysis.driving_behavior(client, sid, tid, trid)
behaviour.harsh_acceleration_count
hd(behaviour.harsh_acceleration.points)   # %Amap.Falcon.TrackAnalysis.Event{}

{:ok, stays} =
  Amap.Falcon.TrackAnalysis.stay_points(client, sid, tid, trid, stay_radius: 100)

{:ok, match} =
  Amap.Falcon.TrackMatch.match(client, {sid, tid, trid}, {sid, other_tid, other_trid},
    is_points: true
  )

match.match_ratio   # "84.7" — Amap sends a string, and it is kept as one
```

`TrackMatch.match/4` sends a **JSON body**, which is why `Amap.request/6` takes
`body: :form | :json`; everything else here is a GET or a form POST.

**One Falcon endpoint is not wrapped:** `Amap.Falcon.Etc` (toll estimation) is open
only to enterprise developers, so it could not be exercised against the live
service and was deferred rather than guessed at until an account exists for it.

## Web service API

The Web service host — `restapi.amap.com` — answers with a flat `{status, info,
infocode, …}` envelope, which the same client collapses for you. The simple queries:

```elixir
{:ok, ip} = Amap.IpLocation.ip(client)
ip.province                          # "北京市"

{:ok, [place]} = Amap.Geocoding.geo(client, "北京市朝阳区阜通东大街6号", city: "北京")
place.location                       # {116.480881, 39.989410}
place.level                          # "门牌号": how specific the match is

{:ok, regeo} = Amap.Geocoding.regeo(client, {116.310003, 39.991957}, extensions: :all)
regeo.address_component.city         # "北京市"
length(regeo.pois)                   # nearby POIs, with roads and AOIs beside them

{:ok, converted} = Amap.Convert.convert(client, [{116.481499, 39.990475}], coordsys: :gps)
hd(converted.locations)              # that GPS point in Amap's own system

{:ok, districts} = Amap.District.district(client, keywords: "北京", subdistrict: 1)
hd(districts.items).districts        # its children; every level is the same struct

{:ok, [now]} = Amap.Weather.live(client, "110000")
now.temperature                      # "24"

{:ok, [days]} = Amap.Weather.forecast(client, "110000")
hd(days.casts).dayweather            # "晴"

{:ok, stops} = Amap.Bus.stopname(client, "来广营路口西")
hd(stops.busstops).buslines          # the lines serving a stop

{:ok, lines} = Amap.Bus.linename(client, "地铁1号线", extensions: :all)
hd(lines.buslines).busstops          # the stops a line serves, in sequence order

{:ok, found} = Amap.Place.text(client, keywords: "北京大学", city: "北京")
hd(found.pois).location              # {116.310791, 39.992521}

{:ok, v5} = Amap.NewPlace.text(client, keywords: "北京大学", show_fields: [:business])
hd(v5.pois).business.rating          # "4.7" — only because show_fields asked

{:ok, tips} = Amap.InputTips.inputtips(client, "招商", city: "010")
hd(tips.tips).name                   # "招商银行(北京分行)"

{:ok, corrected} =
  Amap.Grasproad.driving(client, [
    %{location: {116.478928, 39.997761}, ag: 0, tm: 1_478_031_031, sp: 19},
    %{location: {116.478907, 39.998422}, ag: 0, tm: 2, sp: 10}
  ])

corrected.points                     # the road coordinates Amap snapped the track to
corrected.distance                   # the corrected track's length
```

`Amap.Traffic` reads the traffic along a road, inside a circle or inside a
rectangle. It is a **高级服务** interface, which Amap opens per account, so it may
answer with a refusal while every other call on the same key works.

Three things worth knowing before the first surprise. `Amap.Convert` sends
`coordsys` only when you name one, because Amap's own default converts nothing at
all. `Amap.District` returns its matches beside Amap's suggestion list, which is the
only way to see what Amap thought you meant when a keyword matches nothing.
`Amap.Weather`'s two modes answer different fields — current conditions or three
days of forecast — which is why they are two functions rather than one.

`Amap.Bus`'s two keyword searches take `city` optionally, and leaving it out
searches the whole country: `linename`'s page promises a 全国 default and a probe
without a city really did answer lines from another city.

`Amap.Place` and `Amap.NewPlace` are the two generations of POI search — keyword,
around and polygon search plus lookup by id. `city` biases the answer where
`city_limit: true` restricts it; v3 pages with `offset`/`page`, v5 with
`page_size`/`page_num`, and both pages answer at most 200 rows for one query, which is
why the SDK caps the page number instead of letting it ask past the ceiling. v5's
optional groups — `:children`, `:business`, `:indoor`, `:navi`, `:photos` — arrive only
when `show_fields` asks for them. `Amap.InputTips` takes the singular `type` its page
documents, and its `location` only has an effect when `city` is beside it.

`Amap.Grasproad` is 轨迹纠偏 — the one basic page that is neither a route nor a POI.
It takes a driven track of up to 500 points, each a `{lon, lat}` location plus the
page's `ag` (heading from due north), `tm` (seconds: the first point's from 1970, the
rest as differences from it) and `sp` (km/h), and answers where the track really ran.
The live run settles the page's untyped scalars: `distance` is a **number** here
(`696.0`) and each returned point a `{x, y}` pair of floats, unlike the string
distances the v3 and v5 routes send — and Amap **densifies** the corrected track, so 8
sent points came back as 28. The body is a JSON **array**, the SDK's only other JSON
body besides `Amap.Falcon.TrackMatch` — which is why `Amap.Request` accepts a non-empty
list of maps as well as one object. The endpoint answers the Falcon
envelope from the Web service host, the second `/v4/` page to do so, so it is called
with host `:restapi` and `envelope: :tsapi` like `Amap.Direction.bicycling/4`; and
`30001`, the page's 抓路失败 — too few or too sparse points, and what a single point
gets too — arrives as `:grasproad_failed` rather than a generic engine error, though
the wire's own `errmsg` is the generic `ENGINE_RESPONSE_DATA_ERROR`. The SDK refuses a
track outside 1..500 before sending; the service's own 500 rule shows up on a raw
501-object body as `20000` `INVALID_PARAMS`.

## Route planning

Two generations of the same idea, on the same host. `Amap.Direction` is the v3
page — `driving/4`, `walking/4`, `transit/5` and the measuring `distance/4` — plus
the v4 `bicycling/4`; `Amap.NewRoute` is v5's, where optional groups arrive only
when `show_fields` asks for them. Both take their points as `{lon, lat}` tuples:

```elixir
{:ok, route} =
  Amap.Direction.driving(client, {116.397428, 39.90923}, {116.461, 39.9087},
    extensions: :all
  )

[path | _] = route.paths
path.distance     # "8348" — Amap sends distances as strings
hd(path.steps).polyline
# the wire's one `;`-joined string, decoded into `{lon, lat}` tuples
```

`:extensions` is the v3 endpoint's own grouping: only `:all` fills `tmcs`,
`cities` and `districts`, while the page's parameter table marks it required and
its sample says otherwise.

```elixir
{:ok, route} =
  Amap.NewRoute.driving(client, {116.397428, 39.90923}, {116.461, 39.9087},
    show_fields: [:cost, :navi, :polyline]
  )

[path | _] = route.paths
path.cost.duration         # "1317" — a group that was asked for
hd(path.steps).navi.action # "右转" — the group arrives on the step
```

Five things this pair of pages will not tell you. `Amap.Direction.bicycling/4`
lives on the Web service host and answers the **Falcon** envelope, which is why
host and envelope are two axes and why `Amap.request/6` takes `envelope:`;
`Amap.NewRoute.bicycling/4` is its v5 sibling, and `/v4/grasproad/driving` is the
other endpoint of that kind. `ferry: :use` is the **default** on both
generations' driving endpoints: the wire's `0` means *take* the ferry, so the
option is named after the intent rather than the number. v5's `driving/4` takes
`method: :post` for parameters too long to be a URL — with the documented maxima,
16 waypoints and 32 avoid-polygons, the query measured 12,129 bytes, which GET
answered with `:unexpected_response` while POST answered the route. And a v5
`show_fields` group that was not asked for leaves its fields `nil` — so a `nil` there
means the field was not sent at that level; `tmcs` is the exception, a
list that cannot say which it is, because an unasked group and an asked-but-empty one
both arrive `[]`. And on the
walking and riding endpoints `walk_type` arrives **inside each step's `navi`**
rather than on the step where those pages list it as a `show_fields` group — the
probe that saw it there was `/v5/direction/walking`; driving does not return it at
all.

## Swapping the JSON library

```elixir
config :amap, :json_library, Jason
```

The module must provide `decode/1` and `encode!/1`, and must be a dependency of
your own application — this SDK depends on Elixir's built-in `JSON` only.
Both directions are needed: Falcon's `props` parameter carries a JSON object as
a form value, so the SDK encodes request parameters as well as decoding
responses.

## Development

`mix ci` runs everything CI runs:

```
compile --all-warnings --warnings-as-errors
format --check-formatted
credo --strict          # includes the ExSlop AI-slop checks
deps.unlock --check-unused
hex.audit
xref graph --label compile-connected --fail-above 5
dialyzer
ex_dna                  # duplicate code
reach.check --dead-code --smells
test
```

`mix ci.fast` runs the same without the slow static analysis, for the inner loop.
All of the tooling is `dev`/`test` scoped, so none of it reaches consumers of the
package.

### Integration tests

The live checks are tagged `:integration` and excluded from `mix test`; the
`mix integration` alias runs them:

```sh
AMAP_KEY=… mix integration
```

Extra arguments pass through to `mix test`, so
`mix integration test/amap/bus/integration_test.exs` runs one file. Without
`AMAP_KEY` the alias stops with a Mix error rather than running every check
skipped — a green exit that would prove nothing. The tests call Amap for real and
spend real quota, so run them when a page needs the wire, not on every change.

**A refusal is not an answer.** Amap rate-limits per key, and a refused call comes
back as a tiny envelope — 71 bytes in the 2026-09-20 search run — with `status:"0"`
and `infocode:"10022"`. A check that prints `count: nil` or `suggestion: nil` from
such a body has proved nothing: the field is missing because the call was refused,
not because the endpoint does not send it. In that run 输入提示 answered the 71-byte
refusal on pass 1 and a 2,404-byte body on pass 2, and only pass 2's answers were
recorded. Only a full envelope whose `infocode` is `"10000"` is an answer; rerun a
refused call instead of quoting it as a finding.

Some documented answers must not come from the wire at all: a `@moduledoc` example that teaches a
call shape or a decode path is a doctest, run offline against the local test server. How those
work, and which modules carry one, is the naming convention the changelog records.

## License

MIT
