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
  @json_headers [{"content-type", "application/json"}]

  # Supplied by the client, never by the caller — see `reject_reserved!/1`.
  @reserved_params ~w(key sig)

  @doc """
  Builds a Finch request for the given call.

  The key is always injected, and `key` and `sig` are therefore reserved: a
  caller-supplied copy raises, because the SDK cannot tell which one the caller
  meant. `sig` is added only for the Web service family: the Falcon
  documentation never mentions digital signatures, so signing a Falcon request
  would be guessing.

  `body: :json` sends the parameters as a JSON object instead of a form, which one
  Amap endpoint asks for. It keeps the map's shape — nested objects stay nested,
  because `Param.encode/1` would flatten them into string pairs — and is only
  supported for `:tsapi`, where nothing is signed: signing a JSON body is not
  defined, and sending one unsigned to a family that expects signatures would be
  worse than refusing.
  """
  @spec build(Client.t(), Client.family(), :get | :post, String.t(), map() | keyword(), keyword()) ::
          Finch.Request.t()
  def build(%Client{} = client, family, method, path, params, opts \\ []) do
    case Keyword.get(opts, :body, :form) do
      :form -> build_form(client, family, method, path, params)
      :json -> build_json(client, family, method, path, params)
      other -> raise ArgumentError, ":body must be :form or :json, got: #{inspect(other)}"
    end
  end

  defp build_form(client, family, method, path, params) do
    params =
      params
      |> Param.encode()
      |> reject_reserved!()
      |> Keyword.put(:key, client.key)
      |> maybe_sign(client, family, path)

    url = client.base_urls[family] <> path
    encoded = URI.encode_query(params)

    case method do
      :get -> Finch.build(:get, url <> "?" <> encoded)
      :post -> Finch.build(:post, url, @form_headers, encoded)
    end
  end

  defp build_json(_client, family, _method, _path, _params) when family != :tsapi do
    raise ArgumentError,
          "a JSON body is only supported for the :tsapi family, since signing one is not defined"
  end

  defp build_json(%Client{} = client, :tsapi, method, path, params) when is_map(params) do
    body =
      params
      |> reject_reserved_map!()
      |> Map.put("key", client.key)
      |> Amap.JSON.encode!()

    # The key goes in the query string as well as the body. A live call with it only in
    # the JSON body answered 10001 INVALID_USER_KEY, so this service does not read it from
    # there -- and the 轨迹重合度分析 page says nothing about where the key goes. The only page
    # carrying a "key needs to be appended to the url" note is 轨迹上传及管理, on trace/add,
    # where the key in the form body succeeds. Collected with the other page-versus-service
    url = client.base_urls[:tsapi] <> path <> "?" <> URI.encode_query(key: client.key)

    Finch.build(method, url, @json_headers, body)
  end

  defp build_json(%Client{}, :tsapi, _method, _path, params) do
    raise ArgumentError, "a JSON body must be a map, got: #{inspect(params)}"
  end

  # Rejected rather than resolved by a precedence rule, because no rule here can
  # be right. `Param.encode/1` produces string keys while the injection above
  # uses an atom, so a caller's `"key"` is not replaced but *joined*: the wire
  # carries `key=real&key=user`, server-side parsing keeps the caller's value,
  # and the signature covers both entries in an order a server may read
  # differently. The failure reaches the caller as `invalid_key` or
  # `invalid_user_signature` and traces to nothing they configured.
  #
  # Reachable despite being contradictory — Amap's own documentation lists `key`
  # in every example parameter table, so copying one is plausible.
  defp reject_reserved!(params) do
    case Enum.find(@reserved_params, &List.keymember?(params, &1, 0)) do
      nil ->
        params

      reserved ->
        raise ArgumentError,
              "invalid request parameter #{inspect(reserved)}: the client supplies it, so " <>
                "passing it would put two #{reserved} values on the wire; remove it from " <>
                "the parameters"
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
  def send(%Client{} = client, family, method, path, params, opts \\ []) do
    result =
      client
      |> build(family, method, path, params, opts)
      |> Finch.request(client.pool, receive_timeout: client.timeout)

    outcome =
      case result do
        {:ok, %Finch.Response{status: 200} = response} ->
          {:ok, response}

        {:ok, %Finch.Response{} = response} ->
          {:error, Error.unexpected_response(response.status, response.body)}

        {:error, exception} ->
          {:error, Error.from_transport(exception)}
      end

    with_request_context(outcome, method, path, params)
  end

  defp with_request_context({:error, %Error{} = error}, method, path, params) do
    {:error, Error.attach_request(error, method, path, params)}
  end

  defp with_request_context(result, _method, _path, _params), do: result

  # The same rule as `reject_reserved!/1`, for a JSON body: there the parameters
  # are a map rather than a list of string pairs, so the lookup differs but the
  # reason does not.
  defp reject_reserved_map!(params) do
    case Enum.find(@reserved_params, &Map.has_key?(params, &1)) do
      nil ->
        params

      reserved ->
        raise ArgumentError,
              "invalid request parameter #{inspect(reserved)}: the client supplies it, so " <>
                "passing it would put two #{reserved} values on the wire; remove it from " <>
                "the parameters"
    end
  end

  defp maybe_sign(params, %Client{private_key: nil}, _family, _path), do: params

  defp maybe_sign(params, %Client{private_key: private_key}, :restapi, _path) do
    Keyword.put(params, :sig, Signature.sign(params, private_key))
  end

  defp maybe_sign(params, %Client{}, :tsapi, _path), do: params
end
