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

Core only. Business modules (`Amap.Geocoding`, `Amap.Falcon.*`, …) land next;
`Amap.request/5` is the stable entry point they build on.

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

Set `private_key:` to enable Amap's digital signature. Signatures are sent to
the Web service family only; the Falcon documentation does not describe them.

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

## License

MIT
