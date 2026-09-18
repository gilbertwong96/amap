defmodule Amap.Falcon.Terminal do
  @moduledoc """
  Falcon terminals — vehicles, devices, people: anything that reports a position.

  Terminals live under a service. A service holds up to 100,000 of them, and
  `list/2` pages through them 50 at a time.

  `props` carries your own fields, but only ones you have already declared
  through the custom-field endpoints (batch S2b); sending an undeclared field is
  rejected by Amap, not here.
  """

  alias Amap.Falcon.Terminal.Page
  alias Amap.Falcon.Validate
  alias Amap.Numeric

  defstruct [:sid, :tid, :name, :desc, :props, :createtime, :locatetime]

  @type t :: %__MODULE__{
          sid: integer() | nil,
          tid: integer() | nil,
          name: String.t() | nil,
          desc: String.t() | nil,
          props: map() | nil,
          createtime: integer() | nil,
          locatetime: integer() | nil
        }

  @base "/v1/track/terminal"

  @doc """
  Creates a terminal.

  `name` becomes the terminal's display name and **cannot be changed
  afterwards** — Amap says so explicitly, and `update/4` does not accept it back
  for renaming.
  """
  @spec add(Amap.Client.t(), integer(), String.t(), keyword()) ::
          {:ok, t()} | {:error, Amap.Error.t()}
  def add(client, sid, name, opts \\ []) do
    params = [
      sid: sid,
      name: Validate.name!(name, ":name"),
      # Amap documents the same character rules for `desc` as for `name`.
      desc: Validate.optional!(&Validate.name!/2, Keyword.get(opts, :desc), ":desc"),
      props: props_param(Keyword.get(opts, :props))
    ]

    client
    |> Amap.request(:tsapi, :post, @base <> "/add", params)
    |> to_terminal()
  end

  @doc "Deletes a terminal, then returns `{:ok, nil}`. Deleted data is unrecoverable."
  @spec delete(Amap.Client.t(), integer(), integer()) :: {:ok, nil} | {:error, Amap.Error.t()}
  def delete(client, sid, tid),
    do: Amap.request(client, :tsapi, :post, @base <> "/delete", sid: sid, tid: tid)

  @doc """
  Updates a terminal's name, description or `props`.

  **`name` is documented as modifiable here, while `create` says it cannot be
  changed afterwards.** Amap contradicts itself; this function passes it through,
  because the endpoint accepts it. That is also why the terminal's display name is
  worth choosing carefully at creation time.

  `props` is a **partial** update: fields you leave out keep their current values,
  while a field you include with no value is cleared. The same is true of `name`
  and `desc` — an **empty string clears** the stored value, which is different
  from leaving the parameter out.

  Returns `{:ok, nil}` — Amap sends no data for this endpoint.
  """
  @spec update(Amap.Client.t(), integer(), integer(), keyword()) ::
          {:ok, nil} | {:error, Amap.Error.t()}
  def update(client, sid, tid, opts) do
    name = Keyword.get(opts, :name)
    desc = Keyword.get(opts, :desc)
    props = Keyword.get(opts, :props)

    if is_nil(name) and is_nil(desc) and is_nil(props) do
      raise ArgumentError,
            "update requires at least one of :name, :desc or :props; pass a value " <>
              "to change, or an empty string to clear one"
    end

    # `text!/2` rather than `name!/2`: an empty string here is Amap's documented
    # way to clear the stored value, not a mistake.
    params = [
      sid: sid,
      tid: tid,
      name: Validate.optional!(&Validate.text!/2, name, ":name"),
      desc: Validate.optional!(&Validate.text!/2, desc, ":desc"),
      props: props_param(props)
    ]

    Amap.request(client, :tsapi, :post, @base <> "/update", params)
  end

  @doc """
  Lists a service's terminals, 50 per page.

  Returns `%Page{items: [...], count: n}`. `count` is Amap's count for the whole
  result set, not for the page.
  """
  @spec list(Amap.Client.t(), integer(), keyword()) :: {:ok, Page.t()} | {:error, Amap.Error.t()}
  def list(client, sid, opts \\ []) do
    params = [
      sid: sid,
      tid: Keyword.get(opts, :tid),
      name: Validate.optional!(&Validate.name!/2, Keyword.get(opts, :name), ":name"),
      page: validate_page(Keyword.get(opts, :page))
    ]

    case Amap.request(client, :tsapi, :get, @base <> "/list", params) do
      {:ok, payload} ->
        {:ok,
         %Page{
           items: Enum.map(Map.get(payload, "results", []), &to_terminal_struct/1),
           count: Numeric.to_integer(payload["count"])
         }}

      {:error, _} = error ->
        error
    end
  end

  # Confirmed against a live response on 2026-09-17: `tid` is an integer and
  # `name` is a string, which is what `add` and the search results say too. The
  # official response table for this endpoint claims the opposite and is wrong.
  defp to_terminal_struct(payload) do
    %__MODULE__{
      sid: Numeric.to_integer(payload["sid"]),
      tid: Numeric.to_integer(payload["tid"]),
      name: payload["name"],
      desc: payload["desc"],
      props: payload["props"],
      createtime: Numeric.to_integer(payload["createtime"]),
      locatetime: Numeric.to_integer(payload["locatetime"])
    }
  end

  defp to_terminal({:ok, nil}), do: {:ok, nil}
  defp to_terminal({:ok, payload}), do: {:ok, to_terminal_struct(payload)}
  defp to_terminal({:error, _} = error), do: error

  defp props_param(nil), do: nil

  defp props_param(props) when is_map(props), do: Amap.Param.props(props)

  defp props_param(other),
    do: raise(ArgumentError, ":props must be a map, got: #{inspect(other)}")

  defp validate_page(nil), do: nil
  defp validate_page(page), do: Validate.range!(page, ":page", 1, 1_000_000)
end
