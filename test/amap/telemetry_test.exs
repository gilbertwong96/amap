defmodule Amap.TelemetryTest do
  use ExUnit.Case, async: false

  alias Amap.{Client, Telemetry}

  @event [:amap, :request]

  defp client, do: struct!(Client, key: "secret-key-value", private_key: "secret-private")

  defp attach do
    test_pid = self()
    handler_id = "#{inspect(test_pid)}-#{System.unique_integer()}"

    :telemetry.attach_many(
      handler_id,
      [@event ++ [:start], @event ++ [:stop], @event ++ [:exception]],
      &__MODULE__.handle_event/4,
      test_pid
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  # Public because :telemetry has to call it: a module-captured function is what
  # stops :telemetry logging a "local function" warning on every attach, so the
  # pid to reply to travels in the handler config instead of a closure.
  def handle_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry, event, measurements, metadata})
  end

  test "emits start and stop events around the operation" do
    attach()

    assert {:ok, :done} =
             Telemetry.span(client(), :restapi, :get, "/v3/ip", fn ->
               {:ok, :done}
             end)

    assert_receive {:telemetry, [_, _, :start], %{system_time: _}, start_meta}
    assert start_meta.family == :restapi
    assert start_meta.method == :get
    assert start_meta.path == "/v3/ip"
    assert start_meta.timeout == 5_000

    assert_receive {:telemetry, [_, _, :stop], %{duration: duration}, stop_meta}
    assert is_integer(duration)
    assert stop_meta.result == :ok
  end

  test "records the error reason and HTTP status when the operation fails" do
    attach()

    # The detail carries a credential-shaped value so the refutations below can
    # fail: stop_meta/1 picks five diagnostic fields and must not leak the rest
    # of the error.
    error =
      Amap.Error.from_tsapi(
        %{
          "errcode" => 10001,
          "errmsg" => "INVALID_USER_KEY",
          "errdetail" => "key secret-key-value is not valid"
        },
        200
      )

    assert {:error, ^error} =
             Telemetry.span(client(), :tsapi, :get, "/v1/track/service/list", fn ->
               {:error, error}
             end)

    assert_receive {:telemetry, [_, _, :stop], _measurements, stop_meta}
    assert stop_meta.result == :error
    assert stop_meta.reason == :invalid_key
    assert stop_meta.code == 10001
    assert stop_meta.http_status == 200
    refute inspect(stop_meta) =~ "secret-key-value"
    refute inspect(stop_meta) =~ "secret-private"
  end

  test "emits an exception event and re-raises" do
    attach()

    assert_raise RuntimeError, "boom", fn ->
      Telemetry.span(client(), :restapi, :get, "/v3/ip", fn -> raise "boom" end)
    end

    assert_receive {:telemetry, [_, _, :exception], _measurements, _meta}
  end

  test "never puts credentials in the metadata" do
    attach()

    Telemetry.span(client(), :restapi, :get, "/v3/ip", fn -> {:ok, nil} end)

    assert_receive {:telemetry, [_, _, :start], _measurements, meta}
    refute inspect(meta) =~ "secret-key-value"
    refute inspect(meta) =~ "secret-private"
  end
end
