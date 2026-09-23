# Falcon track service

Falcon (猎鹰轨迹服务) is Amap's track service. It lives on its own host —
`tsapi.amap.com` — and answers its own envelope, and each of its calls is a module
function rather than a path, so no caller needs to know a wire format. This page is
the map of it: the resources, which module holds each call, and the rules that are
easy to miss. Each module's own `@moduledoc` carries the quota it has and a runnable
example.

## Reaching it

`Amap.Host` describes the host in full: base URL `https://tsapi.amap.com`, key
parameter `key`, and auth `:key_only`. Signing therefore takes no part here — nothing
in the Falcon documentation describes a `sig` — unlike the flat envelope on
`restapi.amap.com`. A Falcon client is the ordinary client:

```elixir
client = Amap.new(key: System.fetch_env!("AMAP_KEY"))

{:ok, service} = Amap.Falcon.Service.add(client, "fleet-a", desc: "night deliveries")
```

`base_urls:` points a client at a proxy or a local server instead
(`base_urls: %{tsapi: "http://localhost:21617"}`), which is how the doctests run
without a key.

## The resources

```text
service (sid)                  one key holds at most 15
├── terminal (tid)             at most 100_000 per service; list/2 pages 50 at a time
│   └── trace (trid)           at most 500_000 per terminal
│       └── point              at most 100 per upload/5
└── column (custom fields)     at most five terminal fields and five trace fields

geofence (gfid)                at most 1000 per service; 10_000 terminals bound to one fence
```

A `props` field — on a terminal or on a trace — is legal only once it has been
declared through the matching column module. Amap rejects an undeclared one, and the
SDK does not check it: only Amap knows the declaration. A declared type
(`:string`, `:double` or `:int`), and a terminal field's searchable flag (`list: :y`),
cannot be changed afterwards.

## A trajectory end to end

```elixir
# 1. Declare the custom fields first. A props key Amap does not know is rejected.
{:ok, nil} = Amap.Falcon.TerminalColumn.add(client, sid, "plate", :string, list: :y)
{:ok, nil} = Amap.Falcon.TraceColumn.add(client, sid, "driver", :string)

# 2. Service, then a terminal inside it, then a trace for that terminal.
{:ok, service} = Amap.Falcon.Service.add(client, "fleet-a", desc: "night deliveries")
{:ok, terminal} = Amap.Falcon.Terminal.add(client, service.sid, "truck-01", props: %{"plate" => "AB1234"})
{:ok, trace} = Amap.Falcon.Trace.add(client, service.sid, terminal.tid, trname: "morning")

# 3. Upload points. Amap keeps the valid ones in a batch it only partly accepts.
{:ok, upload} =
  Amap.Falcon.Point.upload(client, service.sid, terminal.tid, trace.trid, [
    %{location: {114.158, 22.279}, locatetime: ~U[2026-09-17 12:00:00Z]},
    %{location: {114.1583, 22.2793}, locatetime: ~U[2026-09-17 12:00:01Z], speed: 40.0}
  ])

upload.errorpoints   # [] when every point was stored, else the indices to send again

# 4. Read it back: the last position, and the corrected trajectory.
{:ok, position} = Amap.Falcon.TerminalMonitor.lastpoint(client, service.sid, terminal.tid)
position.location   # {114.158, 22.279}

{:ok, found} =
  Amap.Falcon.Grasproad.trsearch(client, service.sid, terminal.tid,
    trid: trace.trid,
    correction: [mapmatch: true, threshold: 20]
  )

found.tracks |> hd() |> Map.get(:points) |> hd()   # %Amap.Falcon.Position{}
```

## Every call

| Module | Path | Calls |
|---|---|---|
| `Amap.Falcon.Service` | `/v1/track/service` | `add/2` · `update/3` · `delete/2` · `list/1` |
| `Amap.Falcon.Terminal` | `/v1/track/terminal` | `add/3` · `update/4` · `delete/3` · `list/2` |
| `Amap.Falcon.Trace` | `/v1/track/trace` | `add/3` · `delete/4` |
| `Amap.Falcon.Point` | `/v1/track/point` | `upload/5` |
| `Amap.Falcon.TerminalColumn` | `/v1/track/terminal/column` | `add/4` · `delete/3` · `update/4` · `list/2` |
| `Amap.Falcon.TraceColumn` | `/v1/track/point/column` | `add/4` · `delete/3` · `update/4` · `list/2` |
| `Amap.Falcon.TerminalSearch` | `/v1/track/terminal` | `search/3` · `aroundsearch/3` · `polygonsearch/3` · `districtsearch/3` |
| `Amap.Falcon.TerminalMonitor` | `/v1/track/terminal` | `lastpoint/3` |
| `Amap.Falcon.Grasproad` | `/v1/track/terminal` | `trsearch/3` · `roaddata/2` |
| `Amap.Falcon.Geofence` | `/v1/track/geofence` | `add_circle/3` · `add_polygon/3` · `add_polyline/3` · `add_district/3` · each `update_*` · `delete/3` · `list/2` · `shapes/0` |
| `Amap.Falcon.FenceTerminal` | `/v1/track/geofence/terminal` | `bind/4` · `unbind/4` · `list/3` |
| `Amap.Falcon.FenceStatus` | `/v1/track/geofence` | `terminal/3` · `location/3` |
| `Amap.Falcon.TrackAnalysis` | `/v1/track/analysis` | `driving_behavior/4` · `stay_points/4` |
| `Amap.Falcon.TrackMatch` | `/v1/track/match` | `match/3` |

The arities are the minimums: most calls take an options list as well. `TraceColumn`'s
paths say `point/column` because Amap's do, but the fields are *trace* fields —
`Amap.Falcon.Point.upload/5`'s `props` and the `props` `trsearch/4` reads back.

Five modules are not endpoints: `Amap.Falcon.Wire` (Amap's dialect — comma-joined ids,
`1`/`0` flags, `"#all"`), `Amap.Falcon.Correction` (`correction` and the rules for a time
window), `Amap.Falcon.Paging` and `Amap.Falcon.Columns` (what the endpoint modules
`use`), and `Amap.Falcon.Position` (the struct a last position and a corrected point
both decode into).

## Rules that are easy to miss

* **Coordinates are `{lon, lat}`, here and everywhere else in this SDK.** The two
  endpoints whose wire form is the opposite order — the search endpoints' centre and
  polygon — reverse it internally.
* **A caller mistake raises, an Amap failure is an error tuple.** A name that breaks
  Amap's character rules, a radius out of range, a filter that cannot be encoded, a
  missing fence parameter: all `ArgumentError` before any request is built. Everything
  else is `{:ok, struct} | {:error, %Amap.Error{}}`, with `{:ok, nil}` for the endpoints
  Amap answers without a `data` body.
* **`filter` and `sort` are Elixir terms.** `filter: [name: ["a", "b"], lastloctime:
  {:>=, 1_469_817_532}]` and `sort: {:lastloctime, :desc}` — not Amap's `&&`, `|` and
  `field:asc`.
* **A page is `%{items: [...], count: n}`.** Passing `gfids` to a fence-status call
  turns pagination off at Amap's end, so those answers are not pages.
* **`lastpoint/3` defaults to road-snapping**, under which a short track can succeed
  with `location: nil`. `correction: :n` answers the point as it was uploaded.
* **`trsearch/3` takes either a `trid` or a `:starttime`/`:endtime` window of at most
  24 hours that does not end in the future.** `roaddata/2` is an advanced service Amap
  enables by ticket.
* **`TrackMatch.match/3` is the one call with a JSON body**, which is why
  `Amap.request/6` takes `body: :json`. `match_ratio` arrives as a string (`"84.7"`)
  and is kept as one.
* **A `Position` may carry values nobody sent.** Road-snapping reported `speed` 255 and
  `direction` 511 for points that had only a location and a time, so a `nil` there
  means "not derived", not "zero".

## Trying it without a key

The suite's stand-in serves canned responses from a fixed port, which is what the
doctests in each module use. Outside ExUnit — whose `start_supervised!` it is built on —
start it by hand:

```elixir
$ MIX_ENV=test iex -S mix

{:ok, pid} = Amap.TestServer.start_link(port: 21_617)
server = %Amap.TestServer{pid: pid, port: GenServer.call(pid, :port), unconsumed: :counters.new(1, [])}

Amap.TestServer.expect(server, "POST", "/v1/track/service/add", fn _request ->
  {200, ~s({"errcode":10000,"errmsg":"OK","data":{"sid":1000,"name":"fleet-a"}})}
end)

client = Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
Amap.Falcon.Service.add(client, "fleet-a")
```

Live checks are tagged `:integration` and need a real key:
`AMAP_KEY=… mix integration` (`test/amap/falcon/integration_test.exs`).

## Not wrapped

`Amap.Falcon.Etc` — toll estimation (轨迹收费计算) — is open only to enterprise
developers, so it could not be exercised against the live service and was deferred
rather than guessed at until an account exists for it.
