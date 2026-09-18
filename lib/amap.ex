defmodule Amap do
  @moduledoc """
  Amap (高德地图) Web API client.

  Two API families share one core: the Web service API (`restapi.amap.com`) and
  the Falcon track service (`tsapi.amap.com`). Both authenticate with the same
  Web service type key, and both return HTTP 200 even when the body reports an
  error, so status codes are never used to detect failures.
  """

  alias Amap.Client
  alias Amap.Error
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

  This is the entry point every business module uses. It normalizes both API
  families, so callers get the bare payload map regardless of which envelope
  came back.

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

  `opts` may carry `host:` (defaulting to `family`), naming the base URL to use
  when an endpoint's host is not its family's. `/v4/direction/bicycling` is one
  such endpoint: it answers the Falcon envelope from `restapi.amap.com`, so it is
  called as `:tsapi` with `host: :restapi`. The family keeps deciding the envelope
  and the signature — only the destination changes.

  Raises `ArgumentError` if `family` is neither `:restapi` nor `:tsapi`, if `opts`
  names a `:host` other than those two, or if `params` supplies `key` or `sig`. The
  client owns both of those: injecting a second copy would put two `key` parameters
  on the wire, and the signed string would no longer be the one the server reads.
  """
  @spec request(
          Client.t(),
          Client.family(),
          :get | :post,
          String.t(),
          Amap.JSON.props() | keyword()
        ) ::
          {:ok, Response.payload()} | {:error, Error.t()}
  def request(client, family, method, path, params, opts \\ [])

  def request(%Amap.Client{} = client, family, method, path, params, opts)
      when family in [:restapi, :tsapi] do
    attempt(client, family, method, path, params, opts, 0)
  end

  # An unknown family would otherwise reach `client.base_urls[family]`, which is
  # nil, and die with "construction of binary failed: ... got: nil" — naming
  # neither the argument nor its valid values.
  def request(%Amap.Client{}, family, _method, _path, _params, _opts) do
    raise ArgumentError, "invalid family: #{inspect(family)}; expected :restapi or :tsapi"
  end

  # One attempt, plus at most `max_attempts/1` more. Each attempt gets its own
  # telemetry span, so a retried call shows up as several spans rather than one
  # long one, and the span that failed keeps its own error metadata.
  #
  # Exhaustion returns the last failure unchanged — same struct, same reason —
  # because callers branch on `%Amap.Error{}` and `Amap.Telemetry.stop_meta/1`
  # has no catch-all clause.
  defp attempt(client, family, method, path, params, opts, attempt) do
    result =
      Telemetry.span(client, family, method, path, fn ->
        with :ok <- acquire(client, family, path),
             {:ok, response} <- Request.send(client, family, method, path, params, opts),
             {:ok, payload} <- decode(response.body, response.status) do
          Response.normalize(family, payload, response.status)
        end
      end)

    case result do
      {:error, %Amap.Error{} = error} ->
        if attempt < max_attempts(client) and error.retry != :no do
          Process.sleep(delay(error, client, attempt))
          attempt(client, family, method, path, params, opts, attempt + 1)
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
  defp acquire(%Amap.Client{limiter: nil}, _family, _path), do: :ok

  defp acquire(%Amap.Client{limiter: limiter, timeout: timeout}, family, path) do
    started = System.monotonic_time()

    result =
      case Limiter.acquire(limiter, timeout) do
        :ok -> :ok
        {:error, :timeout} -> {:error, Error.limiter_timeout()}
      end

    report_queue_wait(started, family, path)
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
  defp report_queue_wait(started, family, path) do
    wait_ms =
      System.monotonic_time()
      |> Kernel.-(started)
      |> System.convert_time_unit(:native, :millisecond)

    if wait_ms > 0 do
      :telemetry.execute([:amap, :limiter, :queued], %{wait_ms: wait_ms}, %{
        family: family,
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
