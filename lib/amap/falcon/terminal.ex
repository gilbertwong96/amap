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
    params =
      [sid: sid, name: Validate.name!(name, ":name")] ++
        optional(desc: Keyword.get(opts, :desc), props: props_param(Keyword.get(opts, :props)))

    client
    |> Amap.request(:tsapi, :post, @base <> "/add", params)
    |> to_terminal()
  end

  @doc "Deletes a terminal, then returns `{:ok, nil}`. Deleted data is unrecoverable."
  @spec delete(Amap.Client.t(), integer(), integer()) :: {:ok, nil} | {:error, Amap.Error.t()}
  def delete(client, sid, tid),
    do: Amap.request(client, :tsapi, :post, @base <> "/delete", sid: sid, tid: tid)

  @doc """
  Updates a terminal's description or `props`.

  `props` is a **partial** update: fields you leave out keep their current
  values, while a field you include with no value is cleared. That asymmetry is
  Amap's, and it is the reason this function sends only what you pass.

  Returns `{:ok, nil}` — Amap sends no data for this endpoint.
  """
  @spec update(Amap.Client.t(), integer(), integer(), keyword()) ::
          {:ok, nil} | {:error, Amap.Error.t()}
  def update(client, sid, tid, opts) do
    fields =
      optional(
        desc: validate_optional(&Validate.name!/2, Keyword.get(opts, :desc), ":desc"),
        props: props_param(Keyword.get(opts, :props))
      )

    if fields == [] do
      raise ArgumentError,
            "update requires at least one of :desc or :props; pass a value to change"
    end

    Amap.request(client, :tsapi, :post, @base <> "/update", [sid: sid, tid: tid] ++ fields)
  end

  @doc """
  Lists a service's terminals, 50 per page.

  Returns `%Page{items: [...], count: n}`. `count` is Amap's count for the whole
  result set, not for the page.
  """
  @spec list(Amap.Client.t(), integer(), keyword()) :: {:ok, Page.t()} | {:error, Amap.Error.t()}
  def list(client, sid, opts \\ []) do
    params =
      [sid: sid] ++
        optional(
          tid: Keyword.get(opts, :tid),
          name: validate_optional(&Validate.name!/2, Keyword.get(opts, :name), ":name"),
          page: validate_page(Keyword.get(opts, :page))
        )

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

  # Types stay permissive until the live integration test confirms what this
  # endpoint really sends: the official response table for `list` contradicts the
  # one for `add` about `name` and `tid`.
  defp to_terminal_struct(payload) do
    %__MODULE__{
      sid: Numeric.to_integer(payload["sid"]),
      tid: payload["tid"],
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

  defp optional(pairs), do: for({key, value} <- pairs, not is_nil(value), do: {key, value})

  defp validate_optional(_validator, nil, _field), do: nil
  defp validate_optional(validator, value, field), do: validator.(value, field)
end
