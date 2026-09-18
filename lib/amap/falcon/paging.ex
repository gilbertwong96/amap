defmodule Amap.Falcon.Paging do
  @moduledoc """
  Turns Amap's `{count, results}` answer into an endpoint's page struct.

  Several Falcon endpoints answer a page the same way — a `count` for the whole
  result set and a `results` array — and map each row into a struct of their own.
  This holds that shape once, and each module supplies its page struct and its
  mapper.
  """

  alias Amap.Numeric

  @doc """
  Builds `module`'s page struct from a request result.

  `mapper` turns one row into a struct. An error passes through untouched.
  """
  @spec from(term(), module(), (map() -> struct())) ::
          {:ok, struct()} | {:error, Amap.Error.t()}
  def from({:ok, payload}, module, mapper) do
    {:ok,
     struct(module,
       items: Enum.map(Map.get(payload, "results", []), mapper),
       count: Numeric.to_integer(payload["count"])
     )}
  end

  def from({:error, _} = error, _module, _mapper), do: error
end
