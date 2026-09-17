defmodule Amap.LimiterTest do
  use ExUnit.Case, async: true

  alias Amap.Limiter

  defp start!(opts), do: start_supervised!({Limiter, opts})

  test "acquiring with no limiter is a no-op" do
    assert Limiter.acquire(nil, 1_000) == :ok
  end

  test "allows as many immediate acquires as there are tokens" do
    limiter = start!(rate: 2, burst: 2)

    assert Limiter.acquire(limiter, 100) == :ok
    assert Limiter.acquire(limiter, 100) == :ok
  end

  test "makes the caller wait once tokens run out" do
    limiter = start!(rate: 10, burst: 1)

    assert Limiter.acquire(limiter, 1_000) == :ok

    started = System.monotonic_time(:millisecond)
    assert Limiter.acquire(limiter, 1_000) == :ok
    elapsed = System.monotonic_time(:millisecond) - started

    # One token at 10/s means roughly 100ms; allow generous scheduling slack.
    assert elapsed >= 50
  end

  test "returns an error instead of raising when waiting exceeds the timeout" do
    limiter = start!(rate: 1, burst: 1)

    assert Limiter.acquire(limiter, 1_000) == :ok
    assert Limiter.acquire(limiter, 10) == {:error, :timeout}
  end

  test "refills up to the burst ceiling and no further" do
    limiter = start!(rate: 10, burst: 2)

    assert Limiter.acquire(limiter, 1_000) == :ok
    assert Limiter.acquire(limiter, 1_000) == :ok

    # 500ms at 10/s would be five tokens; the bucket must cap at the burst size.
    # A token at 10/s is 100ms away, so a 10ms wait must fail.
    Process.sleep(500)

    assert Limiter.acquire(limiter, 100) == :ok
    assert Limiter.acquire(limiter, 100) == :ok
    assert Limiter.acquire(limiter, 10) == {:error, :timeout}
  end

  test "a waiter that gave up does not consume a token" do
    limiter = start!(rate: 1, burst: 1)

    assert Limiter.acquire(limiter, 100) == :ok
    assert Limiter.acquire(limiter, 10) == {:error, :timeout}

    # The abandoned waiter is dropped, so the token that refills at ~1000ms is
    # still available rather than having been spent on a caller that left.
    Process.sleep(1_050)

    assert Limiter.acquire(limiter, 100) == :ok
  end

  test "serves waiters in the order they arrived" do
    limiter = start!(rate: 20, burst: 1)
    assert Limiter.acquire(limiter, 1_000) == :ok

    parent = self()

    for n <- 1..3 do
      spawn(fn ->
        Limiter.acquire(limiter, 5_000)
        send(parent, {:served, n})
      end)

      # Stagger the arrivals so the queue order is deterministic.
      Process.sleep(20)
    end

    assert_receive {:served, 1}, 1_000
    assert_receive {:served, 2}, 1_000
    assert_receive {:served, 3}, 1_000
  end

  describe "presets" do
    test "expands :personal to the individual developer quota" do
      assert Limiter.preset(:personal) == [rate: 30, burst: 30]
    end

    test "expands :enterprise to the enterprise quota" do
      assert Limiter.preset(:enterprise) == [rate: 50, burst: 50]
    end
  end

  describe "Amap.new/1 with a limiter" do
    test "leaves limiter nil when not configured" do
      assert Amap.new(key: "k").limiter == nil
    end

    test "starts a bucket for a preset" do
      client = Amap.new(key: "k", limiter: :personal)

      assert is_pid(client.limiter)
      assert Process.alive?(client.limiter)
    end

    test "starts a bucket for explicit values" do
      client = Amap.new(key: "k", limiter: [rate: 5, burst: 5])

      assert is_pid(client.limiter)
      assert Limiter.acquire(client.limiter, 100) == :ok
    end

    test "rejects a non-positive rate" do
      assert_raise ArgumentError,
                   ~r/invalid :limiter option: \[rate: 0, burst: 5\].*positive :rate/,
                   fn -> Amap.new(key: "k", limiter: [rate: 0, burst: 5]) end
    end

    test "reports a malformed limiter list instead of raising MatchError" do
      assert_raise ArgumentError,
                   ~r/invalid :limiter option: \[rate: 5\].*:burst/,
                   fn -> Amap.new(key: "k", limiter: [rate: 5]) end
    end

    test "rejects a non-positive burst" do
      assert_raise ArgumentError,
                   ~r/invalid :limiter option: \[rate: 5, burst: 0\].*positive :rate/,
                   fn -> Amap.new(key: "k", limiter: [rate: 5, burst: 0]) end
    end

    test "rejects a negative burst" do
      assert_raise ArgumentError,
                   ~r/invalid :limiter option: \[rate: 5, burst: -1\]/,
                   fn -> Amap.new(key: "k", limiter: [rate: 5, burst: -1]) end
    end
  end

  describe "a non-positive rate" do
    test "fails at construction rather than killing the caller at the second acquire" do
      # `rate: 0` sets `per_ms: 0.0`, which `schedule/1` divides by, raising
      # `:badarith` as an exit `acquire/2` does not match — so the caller was
      # killed and the bucket died with it. It must fail to start instead.
      assert {:error, _reason} = Limiter.Supervisor.start_bucket(rate: 0, burst: 5)

      # A private supervisor proves the failed start adds no child, without
      # racing the global one that other async modules also touch.
      sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

      assert {:error, _reason} = DynamicSupervisor.start_child(sup, {Limiter, rate: 0, burst: 5})
      assert DynamicSupervisor.count_children(sup).active == 0
    end
  end

  describe "a non-positive burst" do
    test "fails at construction instead of failing every acquire as if rate-limited" do
      # `burst: 0` sets `capacity` and `tokens` to 0, and `refill/1`'s
      # `min(capacity * 1.0, …)` then clamps the bucket permanently shut: every
      # `acquire/2` blocks its whole timeout and returns `{:error, :timeout}`,
      # which the pipeline reports as `:limiter_timeout` — indistinguishable
      # from genuinely being held at quota, pointing at nothing in the caller's
      # own config.
      assert {:error, _reason} = Limiter.Supervisor.start_bucket(rate: 5, burst: 0)

      sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

      assert {:error, _reason} = DynamicSupervisor.start_child(sup, {Limiter, rate: 5, burst: 0})
      assert DynamicSupervisor.count_children(sup).active == 0
    end

    test "rejects a negative burst, which cannot refill past zero either" do
      assert {:error, _reason} = Limiter.Supervisor.start_bucket(rate: 5, burst: -1)

      sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

      assert {:error, _reason} = DynamicSupervisor.start_child(sup, {Limiter, rate: 5, burst: -1})
      assert DynamicSupervisor.count_children(sup).active == 0
    end
  end
end
