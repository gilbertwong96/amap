defmodule Amap.LimiterTelemetryTest do
  use ExUnit.Case, async: false

  @event [:amap, :limiter, :queued]

  # A port nothing listens on. The limiter gates before HTTP, so a queued or
  # timed-out acquire never reaches it, and an immediate acquire reports a
  # transport failure without needing a server.
  @refused %{restapi: "http://127.0.0.1:1", tsapi: "http://127.0.0.1:1"}

  defp attach do
    test_pid = self()
    handler_id = "#{inspect(test_pid)}-#{System.unique_integer()}"

    :telemetry.attach(handler_id, @event, &__MODULE__.handle_event/4, test_pid)

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  # Public because :telemetry has to call it: a module-captured function is what
  # stops :telemetry logging a "local function" warning on every attach, so the
  # pid to reply to travels in the handler config instead of a closure.
  def handle_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry, event, measurements, metadata})
  end

  defp client(limiter, timeout) do
    Amap.new(key: "secret-key-value", limiter: limiter, timeout: timeout, base_urls: @refused)
  end

  test "stays silent when a token is available" do
    attach()

    # A fresh bucket holds its token, so this acquire does not queue.
    assert {:error, %Amap.Error{reason: :transport}} =
             Amap.request(client([rate: 1, burst: 1], 1_000), :restapi, :get, "/v3/ip", %{})

    refute_received {:telemetry, @event, _measurements, _meta}
  end

  test "emits wait_ms when a token is unavailable" do
    attach()

    starved = client([rate: 1, burst: 1], 30)

    # The first call spends the only token immediately. It does not refill for a
    # full second, so the second call genuinely waits — and times out, which is
    # when a caller waits longest.
    assert {:error, %Amap.Error{reason: :transport}} =
             Amap.request(starved, :restapi, :get, "/v3/ip", %{})

    refute_received {:telemetry, @event, _measurements, _meta}

    assert {:error, %Amap.Error{reason: :limiter_timeout}} =
             Amap.request(starved, :restapi, :get, "/v3/ip", %{})

    assert_receive {:telemetry, @event, %{wait_ms: wait_ms}, meta}
    assert is_integer(wait_ms)
    assert wait_ms >= 0
    assert meta.host == :restapi
    assert meta.path == "/v3/ip"
    refute inspect(meta) =~ "secret-key-value"
  end

  test "emits nothing for a client with no limiter" do
    attach()

    assert {:error, %Amap.Error{reason: :transport}} =
             Amap.request(Amap.new(key: "k", base_urls: @refused), :restapi, :get, "/v3/ip", %{})

    refute_received {:telemetry, @event, _measurements, _meta}
  end
end
