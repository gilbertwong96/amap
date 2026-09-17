defmodule Amap.Request do
  @moduledoc """
  Builds and performs Amap HTTP requests.

  Parameters travel as a query string on GET and as an
  `application/x-www-form-urlencoded` body on POST, matching what the API
  accepts. Signing happens on raw values before URL encoding, which is what the
  signature algorithm specifies.
  """

  alias Amap.{Client, Error, Param, Signature}

  @form_headers [{"content-type", "application/x-www-form-urlencoded"}]

  @doc """
  Builds a Finch request for the given call.

  The key is always injected. `sig` is added only for the Web service family:
  the Falcon documentation never mentions digital signatures, so signing a
  Falcon request would be guessing.
  """
  @spec build(Client.t(), Client.family(), :get | :post, String.t(), map() | keyword()) ::
          Finch.Request.t()
  def build(%Client{} = client, family, method, path, params) do
    params =
      params
      |> Param.encode()
      |> Keyword.put(:key, client.key)
      |> maybe_sign(client, family, path)

    url = client.base_urls[family] <> path
    encoded = URI.encode_query(params)

    case method do
      :get -> Finch.build(:get, url <> "?" <> encoded)
      :post -> Finch.build(:post, url, @form_headers, encoded)
    end
  end

  @doc """
  Sends a request and normalizes transport-level outcomes.

  An HTTP status other than 200 is reported as `:unexpected_response`: Amap
  signals its own failures in the body with a 200 status, so anything else came
  from a proxy or gateway rather than the API.
  """
  @spec send(Client.t(), Client.family(), :get | :post, String.t(), map() | keyword()) ::
          {:ok, Finch.Response.t()} | {:error, Error.t()}
  def send(%Client{} = client, family, method, path, params) do
    result =
      client
      |> build(family, method, path, params)
      |> Finch.request(client.pool, receive_timeout: client.timeout)

    case result do
      {:ok, %Finch.Response{status: 200} = response} ->
        {:ok, response}

      {:ok, %Finch.Response{} = response} ->
        {:error, Error.unexpected_response(response.status, response.body)}

      {:error, exception} ->
        {:error, Error.from_transport(exception)}
    end
    |> with_request_context(method, path, params)
  end

  defp with_request_context({:error, %Error{} = error}, method, path, params) do
    {:error, Error.attach_request(error, method, path, params)}
  end

  defp with_request_context(result, _method, _path, _params), do: result

  defp maybe_sign(params, %Client{private_key: nil}, _family, _path), do: params

  defp maybe_sign(params, %Client{private_key: private_key}, :restapi, _path) do
    Keyword.put(params, :sig, Signature.sign(params, private_key))
  end

  defp maybe_sign(params, %Client{}, :tsapi, _path), do: params
end
