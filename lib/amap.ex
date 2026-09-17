defmodule Amap do
  @moduledoc """
  Amap (高德地图) Web API client.

  Two API families share one core: the Web service API (`restapi.amap.com`) and
  the Falcon track service (`tsapi.amap.com`). Both authenticate with the same
  Web service type key, and both return HTTP 200 even when the body reports an
  error, so status codes are never used to detect failures.
  """

  @options [:key, :private_key, :pool, :limiter, :timeout, :retry, :base_urls]

  @doc """
  Builds a client.

  Options fall back to `config :amap`, so a key set once in config does not need
  to be repeated at every call site.
  """
  @spec new(keyword()) :: Amap.Client.t()
  def new(opts \\ []) do
    opts =
      config()
      |> Keyword.merge(opts)
      |> resolve_limiter()

    validate!(opts)
    struct!(Amap.Client, opts)
  end

  defp config do
    # Drop nil values before falling back, so a key that is present but nil
    # counts as unset and does not mask the top-level shorthand.
    from_client =
      Application.get_env(:amap, :client, [])
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
        Keyword.put(opts, :limiter, start_limiter(Amap.Limiter.preset(preset)))

      values when is_list(values) ->
        Keyword.put(opts, :limiter, start_limiter(values))

      other ->
        raise ArgumentError,
              "invalid :limiter option: #{inspect(other)}; expected nil, a pid, " <>
                ":personal, :enterprise, or a keyword list such as [rate: 5, burst: 5]"
    end
  end

  defp start_limiter(values) do
    case Amap.Limiter.start(values) do
      {:ok, pid} ->
        pid

      {:error, reason} ->
        raise ArgumentError,
              "invalid :limiter option: #{inspect(values)}; expected a keyword list such as " <>
                "[rate: 5, burst: 5] with a positive :rate; starting the bucket failed: " <>
                format_start_failure(reason)
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
  end
end
