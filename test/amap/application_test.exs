defmodule Amap.ApplicationTest do
  use ExUnit.Case, async: true

  test "starts the default Finch pool" do
    assert Process.whereis(Amap.Finch)
  end

  test "starts the limiter supervisor" do
    assert Process.whereis(Amap.Limiter.Supervisor)
  end

  test "the limiter supervisor is a dynamic supervisor" do
    # Whether a default client owns a bucket is asserted in Task 12, where the
    # test controls its own client and cannot race another module's process.
    assert {:ok, pid} =
             DynamicSupervisor.start_child(Amap.Limiter.Supervisor, {Task, fn -> :ok end})

    assert is_pid(pid)

    DynamicSupervisor.terminate_child(Amap.Limiter.Supervisor, pid)
  end

  test "the limiter supervisor starts a bucket through start_bucket/1" do
    # The test above proves supervisor capability with a Task child, which says
    # nothing about whether a real bucket can start: start_bucket/1 delegates to
    # Amap.Limiter's child_spec, so this is the seam Task 12 depends on.
    assert {:ok, pid} = Amap.Limiter.Supervisor.start_bucket(rate: 5, burst: 5)
    assert is_pid(pid)
    assert Process.alive?(pid)

    on_exit(fn -> DynamicSupervisor.terminate_child(Amap.Limiter.Supervisor, pid) end)
  end
end
