defmodule Amap.Falcon.Service do
  @moduledoc """
  Falcon track services (猎鹰轨迹服务).

  A service is the container every other Falcon resource lives under: terminals
  belong to it, traces belong to terminals. One key may hold at most 15.

  All functions take the client first and return
  `{:ok, struct | [struct] | nil} | {:error, %Amap.Error{}}`.

  ## Examples

  The examples are doctests: they run against a local stand-in, so they need no key
  and never call Amap. `base_urls` is the override the client documents for exactly
  that — a proxy or a local server — and a real call site omits it:
  `Amap.new(key: …)`. The stand-in's payloads are illustrative, not live readings.

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> {:ok, service} = Amap.Falcon.Service.add(client, "车队A", desc: "夜间配送")
      iex> {service.sid, service.name, service.desc}
      {1000, "车队A", "夜间配送"}

  `name` and `desc` obey Amap's naming rules, and one that breaks them is refused
  here rather than by a round trip that answers `Invalid value of field: …`:

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> Amap.Falcon.Service.add(client, "车队 B")
      ** (ArgumentError) :name may only contain Chinese, letters, digits, _ and -

  What `update/3` reports is the name **as it was before the call**, not the one just
  sent; and an update with nothing to change is refused before any request is built:

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> {:ok, before} = Amap.Falcon.Service.update(client, 1000, name: "车队B")
      iex> {before.sid, before.name}
      {1000, "车队A"}
      iex> Amap.Falcon.Service.update(client, 1000, [])
      ** (ArgumentError) update requires at least one of :name or :desc; pass a value to change, or an empty string to clear one
  """

  alias Amap.Numeric
  alias Amap.Validate

  defstruct [:sid, :name, :desc]

  @type t :: %__MODULE__{
          sid: integer() | nil,
          name: String.t() | nil,
          desc: String.t() | nil
        }

  @base "/v1/track/service"

  @doc """
  Creates a service and returns it.

  `name` must be unique within the key and obeys Amap's naming rules (see
  `Amap.Validate.name!/2`), which are enforced here rather than by a round
  trip.
  """
  @spec add(Amap.Client.t(), String.t(), keyword()) :: {:ok, t()} | {:error, Amap.Error.t()}
  def add(client, name, opts \\ []) do
    params = [
      name: Validate.name!(name, ":name"),
      # Amap documents the same character rules for `desc` as for `name`, so it is
      # validated the same way — a space here would otherwise cost a round trip
      # that answers "Invalid value of field: desc".
      desc: Validate.optional!(&Validate.name!/2, Keyword.get(opts, :desc), ":desc")
    ]

    client
    |> Amap.request(:tsapi, :post, @base <> "/add", params)
    |> to_service()
  end

  @doc "Deletes a service and everything in it, then returns `{:ok, nil}`."
  @spec delete(Amap.Client.t(), integer()) :: Amap.Result.t()
  def delete(client, sid), do: Amap.request(client, :tsapi, :post, @base <> "/delete", sid: sid)

  @doc """
  Updates a service's name, description, or both.

  At least one field is required. The returned struct carries the name **as it
  was before this call** — that is what Amap reports, not the new one — and a
  field given as an empty string is cleared.
  """
  @spec update(Amap.Client.t(), integer(), keyword()) :: {:ok, t()} | {:error, Amap.Error.t()}
  def update(client, sid, opts) do
    name = Keyword.get(opts, :name)
    desc = Keyword.get(opts, :desc)

    if is_nil(name) and is_nil(desc) do
      raise ArgumentError,
            "update requires at least one of :name or :desc; pass a value to change, " <>
              "or an empty string to clear one"
    end

    # `text!/2` rather than `name!/2`: an empty string here is Amap's documented
    # way to clear the stored value, not a mistake.
    params = [
      sid: sid,
      name: Validate.optional!(&Validate.text!/2, name, ":name"),
      desc: Validate.optional!(&Validate.text!/2, desc, ":desc")
    ]

    client
    |> Amap.request(:tsapi, :post, @base <> "/update", params)
    |> to_service()
  end

  @doc "Lists every service under the key. Amap returns no count, only the rows."
  @spec list(Amap.Client.t()) :: {:ok, [t()]} | {:error, Amap.Error.t()}
  def list(client) do
    case Amap.request(client, :tsapi, :get, @base <> "/list", []) do
      {:ok, payload} -> {:ok, Enum.map(Map.get(payload, "results", []), &to_service_struct/1)}
      {:error, _} = error -> error
    end
  end

  # Field by field on purpose: a dynamic key-to-atom mapping would grow our atom
  # table with whatever Amap adds next. Absent keys become nil, per spec §6.2.
  defp to_service_struct(payload) do
    %__MODULE__{
      sid: Numeric.to_integer(payload["sid"]),
      name: payload["name"],
      desc: payload["desc"]
    }
  end

  defp to_service({:ok, nil}), do: {:ok, nil}
  defp to_service({:ok, payload}), do: {:ok, to_service_struct(payload)}
  defp to_service({:error, _} = error), do: error
end
