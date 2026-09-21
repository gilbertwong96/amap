defmodule Amap do
  @moduledoc """
  Amap (高德地图) Web API client.

  One core serves every host this SDK describes. `Amap.Host` states each once —
  its base URL, the envelopes it answers and how each authenticates — for the Web
  service API (Web 服务 API, `restapi.amap.com`), the Falcon track service
  (猎鹰轨迹服务, `tsapi.amap.com`), the traffic incident service (交通事件,
  `et-api.amap.com`) and the smart hardware location service v1 (智能硬件定位 v1,
  `apilocate.amap.com`). The hosts a request can reach present the same account
  key, and every host answers HTTP 200 even when the body reports an error, so
  status codes are never used to detect failures.

  ## Examples

  The examples are doctests: they run against a local stand-in, so they need no key
  and never call Amap. `base_urls` is the override the client documents for exactly
  that — a proxy or a local server — and a real call site omits it:
  `Amap.new(key: …)`. The stand-in's payloads are illustrative, not live readings.

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{restapi: "http://localhost:21617"})
      iex> {:ok, payload} = Amap.request(client, :restapi, :get, "/v3/ip", ip: "203.0.113.1")
      iex> Enum.sort(Map.keys(payload))
      ["city", "province"]

  That is the call every business module makes: `request/6` names the host and the
  method, and answers with the bare payload — the `status`/`info`/`infocode` (or
  `errcode`/`errmsg`/`data`) envelope is taken off before the caller sees it. A
  Falcon call with no `data` body answers `{:ok, nil}` rather than `{:ok, %{}}`:

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> Amap.request(client, :tsapi, :post, "/v1/track/service/delete", sid: 1000)
      {:ok, nil}

  The client owns the account key, so a call that tries to supply its own raises
  before a request is built — the wire would carry two values, and which one Amap
  reads is not something the caller controls:

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{restapi: "http://localhost:21617"})
      iex> Amap.request(client, :restapi, :get, "/v3/ip", key: "another-key")
      ** (ArgumentError) invalid request parameter "key": the client supplies it, so passing it would put two key values on the wire; remove it from the parameters
  """

  alias Amap.Client
  alias Amap.Error
  alias Amap.Host
  alias Amap.Limiter
  alias Amap.Request
  alias Amap.Response
  alias Amap.Telemetry

  @options [:key, :private_key, :pool, :limiter, :timeout, :retry, :base_urls]
  @retry_options [:max, :base_delay]

  @doc """
  Builds a client.

  Options fall back to `config :amap`, so a key set once in config does not need
  to be repeated at every call site.
  """
  @spec new(keyword()) :: Client.t()
  def new(opts \\ []) do
    opts =
      config()
      |> Keyword.merge(opts)
      |> resolve_limiter()

    validate!(opts)
    struct!(Amap.Client, opts)
  end

  @default_retry [max: 0, base_delay: 100]

  @doc """
  Performs one Amap call, retrying it when the failure says that is worth doing.

  This is the entry point every business module uses. It normalizes every
  envelope it can parse, so callers get the bare payload map regardless of which
  one came back.

  Retrying is off by default (`retry: [max: 0]`) and, when enabled, is driven by
  the failure itself: `Amap.Error`'s `retry` field is `:immediate` for
  server-side transients, `:backoff` for quota failures Amap suspends the caller
  for, and `:no` for configuration and parameter errors. A reason classified
  `:no` is never retried, however high `:max` is set, because retrying a bad key
  or a missing parameter only spends quota.

  A `:backoff` retry sleeps in the **calling** process, so one call can block it
  for up to `:max` × the window Amap documents — with `max: 2` and the single
  documented window (60_000ms, for `ACCESS_TOO_FREQUENT`) that is on the order
  of two minutes. There is no total-deadline option; lower `:max` to bound it.

  Returns `{:ok, nil}` for Falcon endpoints that answer without a `data` body.

  `host` names the destination — one of `Amap.Host.names()`. `opts[:envelope]`
  names the response envelope when the endpoint's is not the host's default: the
  `/v4/` generation on `restapi.amap.com` answers the Falcon envelope, so
  `/v4/direction/bicycling` is called with host `:restapi` and
  `envelope: :tsapi`. Base URL, signing and the account key's name all come from
  the host's description in `Amap.Host`.

  Raises `ArgumentError` if `host` is not a host this SDK describes, if `opts`
  names an envelope the host does not answer or carries anything but `:envelope`
  and `:body` (the removed `:host:` raises by name rather than being ignored), if
  the host's auth cannot be computed (`:et_api`'s digest is not public), or if
  `params` supplies the host's key parameter or `sig`. The client owns both key
  parameters: injecting a second copy would put two of them on the wire, and the
  signed string would no longer be the one the server reads.
  """
  @spec request(
          Client.t(),
          Host.name(),
          :get | :post,
          String.t(),
          Request.params()
        ) ::
          {:ok, Response.payload()} | {:error, Error.t()}
  @spec request(
          Client.t(),
          Host.name(),
          :get | :post,
          String.t(),
          Request.params(),
          keyword()
        ) ::
          {:ok, Response.payload()} | {:error, Error.t()}
  def request(%Amap.Client{} = client, host, method, path, params, opts \\ []) do
    descriptor = Host.describe(host, Keyword.get(opts, :envelope))
    result = attempt(client, descriptor, method, path, params, opts, 0)

    attach_request(result, method, path, params)
  end

  # `Amap.Request.send/6` attaches the request to the failures it builds, but an
  # envelope refusal, a body that did not parse, and a limiter timeout are built
  # elsewhere. Attaching at the boundary where `request/6` hands the result back
  # to its caller gives every failure the same `%{method:, path:, params:}`. The
  # guard skips an error that already carries one, so the transport path is not
  # masked twice.
  defp attach_request({:error, %Error{request: request} = error}, method, path, params)
       when map_size(request) == 0 do
    {:error, Error.attach_request(error, method, path, params)}
  end

  defp attach_request(result, _method, _path, _params), do: result

  # One attempt, plus at most `max_attempts/1` more. Each attempt gets its own
  # telemetry span, so a retried call shows up as several spans rather than one
  # long one, and the span that failed keeps its own error metadata.
  #
  # Exhaustion returns the last failure unchanged — same struct, same reason —
  # because callers branch on `%Amap.Error{}` and `Amap.Telemetry.stop_meta/1`
  # has no catch-all clause.
  defp attempt(client, %Host{} = descriptor, method, path, params, opts, attempt) do
    result =
      Telemetry.span(client, descriptor.name, method, path, fn ->
        with :ok <- acquire(client, descriptor.name, path),
             {:ok, response} <- Request.send(client, descriptor.name, method, path, params, opts),
             {:ok, payload} <- decode(response.body, response.status) do
          Response.normalize(descriptor.envelope, payload, response.status)
        end
      end)

    case result do
      {:error, %Amap.Error{} = error} ->
        if attempt < max_attempts(client) and error.retry != :no do
          Process.sleep(delay(error, client, attempt))
          attempt(client, descriptor, method, path, params, opts, attempt + 1)
        else
          result
        end

      other ->
        other
    end
  end

  defp max_attempts(%Amap.Client{retry: retry}), do: retry_option(retry, :max)

  # `:immediate` waits nothing, so back-to-back attempts are the caller's
  # choice. `:backoff` prefers the window Amap documents — code 10004 states a
  # one-minute suspension — and falls back to exponential backoff for the
  # quota reasons Amap does not document one for.
  defp delay(%Amap.Error{} = error, %Amap.Client{} = client, attempt) do
    case error.retry do
      :backoff -> error.retry_after || backoff(client, attempt)
      :immediate -> 0
      :no -> 0
    end
  end

  defp backoff(%Amap.Client{retry: retry}, attempt) do
    retry_option(retry, :base_delay) * Integer.pow(2, attempt)
  end

  # `validate!/1` guards `Amap.new/1`, but `Amap.Client` is documented as a
  # plain struct that callers build and pass around, so `struct!(Amap.Client, …)`
  # is a supported path which never sees that validation. These reads must
  # therefore be total for *any* `:retry` shape, or the shapes the constructor
  # rejects return through the other door — each measured on a directly-built
  # client: a non-list dies in `Keyword.get/3` with `FunctionClauseError`; a
  # non-integer `:max` makes the retry guard permanently true (`attempt < nil` is
  # true), and since `:immediate` failures sleep zero that looped at ~7,800
  # requests/second and never returned; and a non-integer `:base_delay` raises
  # `ArithmeticError` from inside `Amap.Telemetry.span/5`, whose `stop_meta/1`
  # has no catch-all clause.
  #
  # One rule covers both keys: a usable value, else the module default. An absent
  # key and an unusable one are the same case — `nil` is Elixir's canonical "not
  # supplied", so `base_delay: nil` from the ordinary `System.get_env/1` idiom is
  # the absent case wearing a present key.
  #
  # One rule rather than two is also what keeps `:base_delay` conservative. Its
  # default is 100ms, and a `:backoff` failure means Amap asked the caller to slow
  # down, so degrading an unusable delay to *no* delay would retry immediately
  # against a server that just said "too frequent" — aggressive on the one axis
  # that matters for a third-party API. For `:max` the default is 0, so a
  # non-integer `:max` still means no retry beyond the first attempt: the total
  # bound is unchanged, and the present-versus-absent distinction that this drops
  # was only ever load-bearing for `:base_delay`, where it pointed the wrong way.
  defp retry_option(retry, key) do
    value = if Keyword.keyword?(retry), do: Keyword.get(retry, key)

    case value do
      value when is_integer(value) and value >= 0 -> value
      _unusable -> @default_retry[key]
    end
  end

  # `Amap.Limiter.acquire/2` speaks `:ok | {:error, :timeout}`, but `request/5`
  # promises `%Amap.Error{}` on every failure path, so the bare atom is wrapped.
  # The wrapped error's reason is `:no` for retry, so a limiter timeout is never
  # retried — waiting longer for a token that never came is not a request that
  # failed for a transient reason.
  defp acquire(%Amap.Client{limiter: nil}, _host, _path), do: :ok

  defp acquire(%Amap.Client{limiter: limiter, timeout: timeout}, host, path) do
    started = System.monotonic_time()

    result =
      case Limiter.acquire(limiter, timeout) do
        :ok -> :ok
        {:error, :timeout} -> {:error, Error.limiter_timeout()}
      end

    report_queue_wait(started, host, path)
    result
  end

  # Emitted only when the caller actually waited: an acquire that finds a token
  # returns in microseconds and measures 0ms, so it stays silent. The event's
  # name means "queued", and firing on every call would make it noise.
  #
  # A timed-out acquire is reported too — it waited longest of all, and knowing
  # that a call spent its whole budget queueing rather than talking to Amap is
  # the difference between a quota problem and a transport one.
  #
  # Metadata is request shape only, as `Amap.Telemetry` does for requests.
  defp report_queue_wait(started, host, path) do
    wait_ms =
      System.monotonic_time()
      |> Kernel.-(started)
      |> System.convert_time_unit(:native, :millisecond)

    if wait_ms > 0 do
      :telemetry.execute([:amap, :limiter, :queued], %{wait_ms: wait_ms}, %{
        host: host,
        path: path
      })
    end
  end

  defp decode(body, status) do
    case Response.decode(body) do
      {:ok, payload} -> {:ok, payload}
      {:error, raw} -> {:error, Error.invalid_json(status, raw)}
    end
  end

  defp config do
    # Drop nil values before falling back, so a key that is present but nil
    # counts as unset and does not mask the top-level shorthand.
    configured = Application.get_env(:amap, :client, [])

    from_client =
      configured
      |> Keyword.take(@options)
      |> Keyword.reject(fn {_k, v} -> is_nil(v) end)

    from_top = Application.get_env(:amap, :key)

    Keyword.put_new(from_client, :key, from_top)
  end

  # Turns the `:limiter` option into a live bucket, so `Amap.Client.limiter`
  # holds a `pid() | nil` as its type claims rather than whatever was passed.
  # Runs after the config merge, so a configured limiter works too.
  defp resolve_limiter(opts) do
    case Keyword.get(opts, :limiter) do
      nil ->
        opts

      value when is_pid(value) ->
        opts

      preset when preset in [:personal, :enterprise] ->
        Keyword.put(opts, :limiter, start_limiter(Limiter.preset(preset)))

      values when is_list(values) ->
        Keyword.put(opts, :limiter, start_limiter(values))

      other ->
        raise ArgumentError,
              "invalid :limiter option: #{inspect(other)}; expected nil, a pid, " <>
                ":personal, :enterprise, or a keyword list such as [rate: 5, burst: 5]"
    end
  end

  defp start_limiter(values) do
    case Limiter.start(values) do
      {:ok, pid} ->
        pid

      {:error, reason} ->
        raise ArgumentError,
              "invalid :limiter option: #{inspect(values)}; expected a keyword list such as " <>
                "[rate: 5, burst: 5] with a positive :rate and :burst; starting the bucket " <>
                "failed: " <> format_start_failure(reason)
    end
  end

  # A failed start arrives in two shapes: a tag `Amap.Limiter.init/1` chose, and
  # the `{exception, stacktrace}` tuple `GenServer.start_link/3` returns when a
  # callback raises — as `Keyword.fetch!/2` does for a missing key. A stacktrace
  # is noise in a configuration error, so only the exception's message is shown.
  defp format_start_failure({reason, stacktrace})
       when is_exception(reason) and is_list(stacktrace) do
    Exception.message(reason)
  end

  defp format_start_failure(reason), do: inspect(reason)

  defp validate!(opts) do
    case Keyword.keys(opts) -- @options do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown option(s): #{inspect(unknown)}"
    end

    unless Keyword.get(opts, :key) do
      raise ArgumentError, ":key is required, pass it to Amap.new/1 or set config :amap, :key"
    end

    validate_retry!(Keyword.get(opts, :retry, []))
  end

  # Validating `:retry`'s *contents* matters more than its key, because every
  # malformed shape here is silent rather than loud: a non-keyword list, an
  # unknown key such as `mx: 2` (a typo for `:max`), or a non-integer value all
  # mean "no retry" once read, so a caller who believes retry is configured gets
  # none. Reading a limit from the environment is the ordinary idiom and
  # `System.get_env/1` never returns an integer — `nil` when unset, a binary when
  # set — so both outcomes arrive here as values to reject.
  #
  # Rejecting them makes all of them a named error at construction, which is what
  # the rest of this module already does for top-level options. `retry_option/2`
  # is the second layer, for clients built as structs directly.
  defp validate_retry!(retry) do
    unless Keyword.keyword?(retry) do
      raise ArgumentError,
            "invalid :retry option: expected a keyword list such as [max: 2, base_delay: 100], " <>
              "got: #{inspect(retry)}"
    end

    case Keyword.keys(retry) -- @retry_options do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "invalid :retry option: unknown key(s) #{inspect(unknown)}; " <>
                "expected only #{inspect(@retry_options)}"
    end

    Enum.each(@retry_options, fn key ->
      case Keyword.fetch(retry, key) do
        :error ->
          :ok

        {:ok, value} when is_integer(value) and value >= 0 ->
          :ok

        {:ok, value} ->
          raise ArgumentError,
                "invalid :retry option: #{inspect(key)} must be a non-negative integer, " <>
                  "got: #{inspect(value)}"
      end
    end)
  end
end
