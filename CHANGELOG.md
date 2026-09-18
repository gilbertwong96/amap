# Changelog

Notable changes to this project, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Amap.new/1` and `%Amap.Client{}`, with defaults that may come from
  application config, and validation that names the option it rejected.
- One `Amap.request/5` entry point for both API families, `restapi` and `tsapi`,
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
  endpoints take, and `Amap.Falcon.Validate` for the rules Amap documents about
  names and ranges, enforced before a request is built rather than by a round trip.
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
