defmodule Amap.Falcon.Service do
  @moduledoc """
  Falcon track services.

  A service is the container every other Falcon resource lives under: terminals
  belong to it, traces belong to terminals. One key may hold at most 15.

  All functions take the client first and return
  `{:ok, struct | [struct] | nil} | {:error, %Amap.Error{}}`.
  """

  alias Amap.Falcon.Validate
  alias Amap.Numeric

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
  `Amap.Falcon.Validate.name!/2`), which are enforced here rather than by a round
  trip.
  """
  @spec add(Amap.Client.t(), String.t(), keyword()) :: {:ok, t()} | {:error, Amap.Error.t()}
  def add(client, name, opts \\ []) do
    params =
      [
        name: Validate.name!(name, ":name")
      ] ++ optional(desc: Keyword.get(opts, :desc))

    client
    |> Amap.request(:tsapi, :post, @base <> "/add", params)
    |> to_service()
  end

  @doc "Deletes a service and everything in it, then returns `{:ok, nil}`."
  @spec delete(Amap.Client.t(), integer()) :: {:ok, nil} | {:error, Amap.Error.t()}
  def delete(client, sid), do: Amap.request(client, :tsapi, :post, @base <> "/delete", sid: sid)

  @doc """
  Updates a service's name, description, or both.

  At least one field is required. The returned struct carries the name **as it
  was before this call** — that is what Amap reports, not the new one — and a
  field given as an empty string is cleared.
  """
  @spec update(Amap.Client.t(), integer(), keyword()) :: {:ok, t()} | {:error, Amap.Error.t()}
  def update(client, sid, opts) do
    fields =
      optional(
        name: validate_optional(&Validate.name!/2, Keyword.get(opts, :name), ":name"),
        desc: validate_optional(&Validate.name!/2, Keyword.get(opts, :desc), ":desc")
      )

    if fields == [] do
      raise ArgumentError,
            "update requires at least one of :name or :desc; pass a value to change"
    end

    client
    |> Amap.request(:tsapi, :post, @base <> "/update", [sid: sid] ++ fields)
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

  # `Param.encode/1` drops nils, so building the list with nils is how an
  # optional parameter stays absent from the request.
  defp optional(pairs), do: for({key, value} <- pairs, not is_nil(value), do: {key, value})

  defp validate_optional(_validator, nil, _field), do: nil
  defp validate_optional(validator, value, field), do: validator.(value, field)
end
