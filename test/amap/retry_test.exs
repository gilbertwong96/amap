defmodule Amap.RetryTest do
  use ExUnit.Case, async: true

  setup do
    server = Amap.TestServer.start!()

    base_urls = %{
      restapi: "http://localhost:#{server.port}",
      tsapi: "http://localhost:#{server.port}"
    }

    {:ok, server: server, base_urls: base_urls}
  end

  @busy ~s({"status":"0","info":"SERVER_IS_BUSY","infocode":"10016"})
  @ok ~s({"status":"1","info":"OK","infocode":"10000","province":"北京市"})
  @invalid_key ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})
  @qps ~s({"status":"0","info":"QPS_HAS_EXCEEDED_THE_LIMIT","infocode":"10014"})

  # Arms a single handler for the route and returns a counter of how many
  # requests it served.
  #
  # `Amap.TestServer` keys expectations by `{method, path}`, so registering a
  # second expectation for one route *replaces* the first instead of queueing
  # behind it. A `for` loop around `expect_once/4` therefore leaves only the last
  # expectation armed, and two sequential `expect_once/4` calls leave only the
  # second — which is how a test can pass without exercising retry at all.
  # One always-answering handler is what lets a route serve every attempt.
  #
  # `bodies` is consumed left to right and the last entry repeats, so
  # `[@busy, @ok]` answers the first attempt with a failure and the rest with
  # success, while `[@busy]` never stops failing.
  defp arm(server, bodies) do
    counter = :counters.new(1, [])

    Amap.TestServer.expect(server, "GET", "/v3/ip", fn _req ->
      n = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)

      {200, Enum.at(bodies, n) || List.last(bodies)}
    end)

    counter
  end

  defp requests(counter), do: :counters.get(counter, 1)

  # One paid `:backoff` retry, returning the wall-clock duration of the whole call.
  #
  # 10014 is the shape that reaches `backoff/2`: it classifies `:backoff` and Amap
  # documents no window for it, so `retry_after` is nil and the `base_delay` arm
  # pays out. An `:immediate` failure would short-circuit the delay and never touch
  # `:base_delay` at all, which is why this uses 10014 rather than 10016.
  #
  # `base_delay: 0` is a *usable* value, so it makes the identical call with no
  # delay — the control the relative assertion below is built on.
  defp time_backoff_retry(server, base_urls, base_delay) do
    client =
      struct!(Amap.Client,
        key: "k",
        base_urls: base_urls,
        retry: [max: 1, base_delay: base_delay]
      )

    counter = arm(server, [@qps, @ok])
    started = System.monotonic_time(:millisecond)

    assert {:ok, %{"province" => "北京市"}} =
             Amap.request(client, :restapi, :get, "/v3/ip", %{})

    elapsed = System.monotonic_time(:millisecond) - started

    assert requests(counter) == 2

    elapsed
  end

  test "does not retry by default", %{server: server, base_urls: base_urls} do
    client = Amap.new(key: "k", base_urls: base_urls)
    counter = arm(server, [@busy])

    assert {:error, error} = Amap.request(client, :restapi, :get, "/v3/ip", %{})
    assert error.reason == :server_is_busy
    assert requests(counter) == 1
  end

  test "retries a retryable failure when enabled", %{server: server, base_urls: base_urls} do
    client = Amap.new(key: "k", base_urls: base_urls, retry: [max: 2])
    counter = arm(server, [@busy, @ok])

    assert {:ok, %{"province" => "北京市"}} =
             Amap.request(client, :restapi, :get, "/v3/ip", %{})

    assert requests(counter) == 2
  end

  test "does not retry a configuration error", %{server: server, base_urls: base_urls} do
    client = Amap.new(key: "k", base_urls: base_urls, retry: [max: 3])
    counter = arm(server, [@invalid_key])

    assert {:error, error} = Amap.request(client, :restapi, :get, "/v3/ip", %{})
    assert error.reason == :invalid_key
    assert requests(counter) == 1
  end

  test "gives up after max attempts", %{server: server, base_urls: base_urls} do
    client = Amap.new(key: "k", base_urls: base_urls, retry: [max: 2])
    counter = arm(server, [@busy])

    assert {:error, error} = Amap.request(client, :restapi, :get, "/v3/ip", %{})
    assert error.reason == :server_is_busy
    assert requests(counter) == 3
  end

  # The `:backoff` fallback arm — `error.retry_after || backoff(client, attempt)`.
  #
  # The precedence itself (`retry_after` winning over `base_delay`) cannot be
  # covered cheaply end to end: the one window Amap documents belongs to
  # `:access_too_frequent` at 60_000ms, and because `||` short-circuits on a
  # non-nil value that test would cost a minute of wall clock. What is cheap is
  # the *fallback* arm, via a `:backoff`-classified code with no window at all.
  test "backs off by base_delay when Amap documents no window", %{
    server: server,
    base_urls: base_urls
  } do
    # Pin the precondition. Without this the test would keep passing if 10014
    # gained a `retry_after`, silently switching from covering the fallback to
    # covering the precedence; and it would fail loudly (not silently) if 10014
    # were reclassified `:immediate`, since then nothing would sleep.
    assert Amap.Error.Code.retry(:qps_exceeded) == :backoff
    assert Amap.Error.Code.retry_after(:qps_exceeded) == nil

    client = Amap.new(key: "k", base_urls: base_urls, retry: [max: 1, base_delay: 20])
    counter = arm(server, [@qps, @ok])

    started = System.monotonic_time(:millisecond)

    assert {:ok, %{"province" => "北京市"}} =
             Amap.request(client, :restapi, :get, "/v3/ip", %{})

    elapsed = System.monotonic_time(:millisecond) - started

    assert requests(counter) == 2
    # A zero delay would land at roughly 0-2ms; this is the arm paying out.
    assert elapsed >= 20
  end

  # A non-integer `:max` is the dangerous shape. Reading a retry limit from the
  # environment is the ordinary idiom and `System.get_env/1` never returns an
  # integer: nil when unset, a binary when set. Elixir's term ordering makes
  # `attempt < nil` and `attempt < "2"` both true, so the retry guard would be
  # permanently true with a zero delay on `:immediate` failures.
  describe "a malformed :retry option" do
    test "rejects a non-integer :max" do
      assert_raise ArgumentError,
                   ~r/:retry option: :max must be a non-negative integer, got: nil/,
                   fn -> Amap.new(key: "k", retry: [max: nil]) end

      assert_raise ArgumentError,
                   ~r/:retry option: :max must be a non-negative integer, got: "2"/,
                   fn -> Amap.new(key: "k", retry: [max: "2"]) end
    end

    test "rejects a negative :max" do
      assert_raise ArgumentError,
                   ~r/:retry option: :max must be a non-negative integer, got: -1/,
                   fn -> Amap.new(key: "k", retry: [max: -1]) end
    end

    test "rejects a nil :base_delay" do
      assert_raise ArgumentError,
                   ~r/:retry option: :base_delay must be a non-negative integer, got: nil/,
                   fn -> Amap.new(key: "k", retry: [max: 2, base_delay: nil]) end
    end

    test "rejects a negative :base_delay" do
      assert_raise ArgumentError,
                   ~r/:retry option: :base_delay must be a non-negative integer, got: -100/,
                   fn -> Amap.new(key: "k", retry: [max: 2, base_delay: -100]) end
    end

    test "rejects a :retry that is not a keyword list" do
      assert_raise ArgumentError, ~r/:retry option: expected a keyword list/, fn ->
        Amap.new(key: "k", retry: 5)
      end
    end

    # A list that is not keyword-shaped reads as "no retry" just as silently as a
    # missing key: `Keyword.get/3` finds no `:max` and the default 0 applies.
    test "rejects a list that is not keyword-shaped" do
      for bad <- [[1, 2], [{"max", 2}], ["max"]] do
        assert_raise ArgumentError, ~r/:retry option: expected a keyword list/, fn ->
          Amap.new(key: "k", retry: bad)
        end
      end
    end

    # The most likely user error of the three, and the most misleading: `mx:` is
    # a typo for `:max`, so the caller believes retry is configured and silently
    # gets none. Rejected against the same allowed set the rest of `new/1` uses.
    test "rejects an unknown key, which would silently mean no retry" do
      assert_raise ArgumentError, ~r/:retry option: unknown key\(s\) \[:mx\]/, fn ->
        Amap.new(key: "k", retry: [mx: 2])
      end

      assert_raise ArgumentError, ~r/:retry option: unknown key\(s\) \[:nope, :mx\]/, fn ->
        Amap.new(key: "k", retry: [nope: 1, mx: 2])
      end
    end

    # The guard must reject the malformed shapes without rejecting any shape it
    # documents, including the boundary value 0.
    test "accepts every shape it documents" do
      for good <- [[], [max: 0], [max: 2], [base_delay: 0], [max: 2, base_delay: 250]] do
        assert %Amap.Client{} = Amap.new(key: "k", retry: good)
      end
    end
  end

  # `Amap.Client` is a plain struct, so a caller can build one without passing
  # through `Amap.new/1` and its validation — the module documents it as
  # something to construct and pass around. The runtime reads must be total too,
  # or the constructor's rejections are only a first line and the same shapes come
  # back through this door.
  #
  # Each case asserts the request *count*. "It returned" would also be satisfied
  # by a loop that merely ran slower than the assertion window, which is the
  # failure being guarded. Timeouts are bounded because an unconditional retry
  # loop answers ~7,800 requests/second locally, so a regression should fail in
  # seconds rather than hang the suite for ExUnit's default minute.
  describe "a client built directly as a struct" do
    @tag timeout: 5_000
    test "a non-integer :max degrades to no retry instead of looping", %{
      server: server,
      base_urls: base_urls
    } do
      for bad <- [nil, "2"] do
        client = struct!(Amap.Client, key: "k", base_urls: base_urls, retry: [max: bad])
        counter = arm(server, [@busy])

        assert {:error, error} = Amap.request(client, :restapi, :get, "/v3/ip", %{})
        assert error.reason == :server_is_busy
        assert requests(counter) == 1
      end
    end

    @tag timeout: 5_000
    test "a non-list :retry degrades to no retry instead of raising", %{
      server: server,
      base_urls: base_urls
    } do
      for bad <- [5, nil, %{max: 2}] do
        client = struct!(Amap.Client, key: "k", base_urls: base_urls, retry: bad)
        counter = arm(server, [@busy])

        assert {:error, error} = Amap.request(client, :restapi, :get, "/v3/ip", %{})
        assert error.reason == :server_is_busy
        assert requests(counter) == 1
      end
    end

    # An unusable `:base_delay` falls back to the documented default, not to zero.
    # This is the one shape `Amap.new/1` cannot produce — it rejects an unusable
    # delay — so a directly-built client is the only way to reach the read, and the
    # value it lands on decides whether a `:backoff` retry waits before retrying.
    #
    # Pinned two ways, because neither alone is sufficient here.
    #
    # Relatively, against a `base_delay: 0` control: both measurements carry the
    # same two local HTTP round trips and both wait on the same `Process.sleep/1`,
    # so the contrast is ~100x. Measured, though, the control comes in at 0-2ms,
    # which makes `control_ms * 10` collapse to 0 and reduces this to "elapsed >
    # 0" — enough to catch the regression only when jitter happens to move one
    # value. So the floor does the real work: `Process.sleep/1` cannot return
    # early, so a call that pays the documented default is guaranteed to measure at
    # least that long, while one that degrades to no delay measures like the
    # control. The control is still read twice and the faster kept, so a stalled
    # run cannot inflate the relative bar into a false failure.
    test "an unusable :base_delay falls back to the default delay, not to none", %{
      server: server,
      base_urls: base_urls
    } do
      # Pin the precondition, as the sibling test does. Without it, a reclassified
      # 10014 or a window appearing for `:qps_exceeded` would turn these calls into
      # 60-second sleeps, and the assertion would take a minute to fail instead of
      # failing fast.
      assert Amap.Error.Code.retry(:qps_exceeded) == :backoff
      assert Amap.Error.Code.retry_after(:qps_exceeded) == nil

      # Mirrors `@default_retry[:base_delay]`, which a test cannot read.
      default_delay_ms = 100

      control_ms =
        min(time_backoff_retry(server, base_urls, 0), time_backoff_retry(server, base_urls, 0))

      for unusable <- [nil, "50", -100] do
        elapsed_ms = time_backoff_retry(server, base_urls, unusable)

        assert elapsed_ms >= default_delay_ms,
               "base_delay: #{inspect(unusable)} must fall back to the #{default_delay_ms}ms " <>
                 "default, but the call took #{elapsed_ms}ms"

        assert elapsed_ms > control_ms * 10,
               "base_delay: #{inspect(unusable)} must fall back to the #{default_delay_ms}ms " <>
                 "default, so the call should be far slower than the #{control_ms}ms no-delay " <>
                 "control, but it took #{elapsed_ms}ms"
      end
    end
  end
end
