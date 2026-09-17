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
    opts = Keyword.merge(config(), opts)
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
