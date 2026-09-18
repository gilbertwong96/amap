defmodule Amap.Limiter do
  @moduledoc """
  A token bucket that paces outbound calls to Amap.

  Disabled unless a client configures one, because Amap's quotas depend on the
  account type and on which service is being called, and silently slowing a
  caller down is worse than telling them to configure a limit.

  Unlike a rejecting rate limiter, `acquire/2` makes the caller wait. Amap's
  quota errors mean "you are suspended for a window", so queueing is the
  behaviour callers actually want. Waiters are served first-in first-out, which
  keeps the queue fair and avoids the herd effect of polling.

  Note that a bucket is per node. Running several BEAM nodes with one Amap key
  multiplies the effective request rate.
  """

  use GenServer

  alias Amap.Limiter.Supervisor

  @presets %{
    personal: [rate: 30, burst: 30],
    enterprise: [rate: 50, burst: 50]
  }

  # Every bucket shares this id, which is safe only because the parent is a
  # `DynamicSupervisor`: it deliberately does not enforce unique ids, so a second
  # `Amap.new(limiter: …)` starts a second bucket. Under a plain `Supervisor` the
  # shared id would instead raise a duplicate-child error.
  #
  # `restart: :temporary` is load-bearing: a restarted bucket would start with a
  # full allowance and so permit a burst beyond the configured quota. A dead pid
  # is recoverable — `acquire/2` turns it into `{:error, :timeout}`.
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  @doc """
  Named quotas. Values come from Amap's published rate limits and may change.

  An unknown name raises `KeyError`. `Amap.new/1` checks the name against
  `:personal` and `:enterprise` before calling this, so its own error names the
  offending `:limiter` option instead.
  """
  @spec preset(:personal | :enterprise) :: options()
  def preset(name), do: Map.fetch!(@presets, name)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @typedoc "The options a bucket takes: its own rate and burst, both positive."
  @type options :: [{:rate, pos_integer()} | {:burst, pos_integer()}]

  @typedoc """
  Why a bucket would not start.

  `{:invalid_rate, rate}` and `{:invalid_burst, burst}` are this SDK's own checks;
  the `{exception, stacktrace}` pair is what `GenServer.start_link/3` answers with
  when `init/1` raises for any other reason.
  """
  @type start_error ::
          {:invalid_rate, number()}
          | {:invalid_burst, number()}
          | {Exception.t(), Exception.stacktrace()}

  @doc """
  Starts a bucket under `Amap.Limiter.Supervisor`.

  Returns `{:error, {:invalid_rate, rate}}` or `{:error, {:invalid_burst, burst}}`
  for a non-positive `:rate` or `:burst`, rather than starting a bucket that
  cannot serve a request.
  """
  @spec start(options()) :: {:ok, pid()} | {:error, start_error()}
  def start(opts), do: Supervisor.start_bucket(opts)

  @doc """
  Waits for a token.

  Waiters carry a deadline rather than relying on the caller's own timeout, so
  a caller that gives up is dropped from the queue instead of silently
  consuming a token later.
  """
  @spec acquire(pid() | nil, timeout()) :: :ok | {:error, :timeout}
  def acquire(nil, _timeout), do: :ok

  def acquire(limiter, timeout) do
    deadline = now() + timeout

    GenServer.call(limiter, {:acquire, deadline}, timeout + 1_000)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, {:noproc, _} -> {:error, :timeout}
  end

  @impl GenServer
  def init(opts) do
    rate = Keyword.fetch!(opts, :rate)
    burst = Keyword.fetch!(opts, :burst)

    cond do
      rate <= 0 ->
        # Rejected rather than clamped or defaulted; neither case is recoverable.
        # Zero makes `per_ms` zero and `schedule/1` divides by it, so the
        # `:badarith` arrives as an exit `acquire/2` does not match: it kills the
        # caller and the bucket with it. Negative divides cleanly, but makes
        # `refill/1` *subtract* tokens, so no token is ever available again and
        # `schedule/1` re-arms a 1ms tick and spins.
        {:stop, {:invalid_rate, rate}}

      burst <= 0 ->
        # Rejected for the same reason as `rate`, and equally unrecoverable.
        # `burst` becomes both `capacity` and the starting `tokens`, and
        # `refill/1` caps at `capacity * 1.0`, so a zero or negative burst clamps
        # the bucket permanently shut: every `acquire/2` blocks its whole timeout
        # and returns `{:error, :timeout}`, which the pipeline reports as
        # `:limiter_timeout` — indistinguishable from genuinely being held at
        # quota, and pointing at nothing in the caller's own config.
        {:stop, {:invalid_burst, burst}}

      true ->
        {:ok,
         %{
           capacity: burst,
           tokens: burst * 1.0,
           per_ms: rate / 1000,
           last: now(),
           waiters: :queue.new(),
           timer: nil
         }}
    end
  end

  @impl GenServer
  def handle_call({:acquire, deadline}, from, state) do
    state = expire(state)

    case take(state) do
      {:ok, state} -> {:reply, :ok, state}
      {:wait, state} -> {:noreply, schedule(enqueue(state, from, deadline))}
    end
  end

  @impl GenServer
  def handle_info(:tick, state) do
    {:noreply, state |> Map.put(:timer, nil) |> expire() |> serve() |> schedule()}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, drop(state, pid)}
  end

  # Waiters that passed their deadline are answered and removed. Without this
  # an abandoned waiter would still be served later, spending a token on a
  # caller that has already given up.
  defp expire(state) do
    {expired, waiting} =
      state.waiters
      |> :queue.to_list()
      |> Enum.split_with(fn {_pid, _ref, _from, deadline} -> deadline <= now() end)

    Enum.each(expired, fn {_pid, ref, from, _deadline} ->
      Process.demonitor(ref, [:flush])
      GenServer.reply(from, {:error, :timeout})
    end)

    %{state | waiters: :queue.from_list(waiting)}
  end

  defp serve(state) do
    state = refill(state)

    case :queue.out(state.waiters) do
      {{:value, {_pid, ref, from, _deadline}}, waiters} when state.tokens >= 1.0 ->
        Process.demonitor(ref, [:flush])
        GenServer.reply(from, :ok)
        serve(%{state | waiters: waiters, tokens: state.tokens - 1.0})

      _ ->
        state
    end
  end

  defp take(state) do
    state = refill(state)

    if state.tokens >= 1.0 do
      {:ok, %{state | tokens: state.tokens - 1.0}}
    else
      {:wait, state}
    end
  end

  defp enqueue(state, {pid, _tag} = from, deadline) do
    ref = Process.monitor(pid)

    %{state | waiters: :queue.in({pid, ref, from, deadline}, state.waiters)}
  end

  defp drop(state, pid) do
    waiters =
      state.waiters
      |> :queue.to_list()
      |> Enum.reject(fn {waiter_pid, _ref, _from, _deadline} -> waiter_pid == pid end)
      |> :queue.from_list()

    %{state | waiters: waiters}
  end

  defp schedule(%{timer: timer} = state) when not is_nil(timer), do: state

  defp schedule(state) do
    if :queue.is_empty(state.waiters) do
      state
    else
      # Refill first so the delay is measured from now, not from the last tick.
      state = refill(state)
      token_delay = max(ceil((1.0 - state.tokens) / state.per_ms), 1)

      delay =
        case earliest_deadline(state) do
          nil -> token_delay
          deadline -> max(min(token_delay, deadline - now()), 1)
        end

      %{state | timer: Process.send_after(self(), :tick, delay)}
    end
  end

  defp earliest_deadline(state) do
    state.waiters
    |> :queue.to_list()
    |> Enum.map(fn {_pid, _ref, _from, deadline} -> deadline end)
    |> Enum.min(fn -> nil end)
  end

  defp refill(state) do
    now = now()
    elapsed = now - state.last

    %{
      state
      | tokens: min(:erlang.float(state.capacity), state.tokens + elapsed * state.per_ms),
        last: now
    }
  end

  defp now, do: System.monotonic_time(:millisecond)
end
