defmodule Amap.StubJSON do
  @moduledoc false
  def decode(_binary), do: {:error, :stub}
  def encode!(_term), do: "stubbed"
end
