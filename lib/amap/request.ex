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

  @typedoc """
  The parameters of a call: the map a form body or the one JSON object
  `track_match` sends, a non-empty list of maps for the JSON array
  `/v4/grasproad/driving` sends, or a keyword list.
  """
  @type params :: Amap.JSON.props() | [Amap.JSON.props()] | keyword()

  @doc """
  Builds a Finch request for the given call.

  The key is always injected, and `key` and `sig` are therefore reserved: a
  caller-supplied copy raises, because the SDK cannot tell which one the caller
  meant. `sig` is added only for the Web service family: the Falcon
  documentation never mentions digital signatures, so signing a Falcon request
  would be guessing.

  `body: :json` sends the parameters as a JSON document instead of a form: an
  object for `/v1/track/match`, and a non-empty list of objects for
  `/v4/grasproad/driving`, whose body is a JSON array. It keeps the map's shape —
  nested objects stay nested, because `Param.encode/1` would flatten them into
  string pairs — and is only supported for `:tsapi`, where nothing is signed:
  signing a JSON body is not defined, and sending one unsigned to a family that
  expects signatures would be worse than refusing. A JSON value that is neither an
  object nor a non-empty list of objects is refused, so the guarantee stays narrow.

  `host:` names the base URL when the endpoint's host is not its family's. Some
  endpoints answer the other family's envelope: `/v4/direction/bicycling` lives on
  `restapi.amap.com` and answers `{errcode, errmsg, errdetail, data}`, so it is
  built as `:tsapi` — the family keeps deciding the parser and the signature — with
  `host: :restapi` deciding where it goes. The default is the family itself, and a
  host outside those two raises `ArgumentError` rather than falling back to the
  family — the same refusal `Amap.request/6` documents.
  """
  @spec build(
          Client.t(),
          Client.family(),
          :get | :post,
          String.t(),
          params(),
          keyword()
        ) ::
          Finch.Request.t()
  def build(%Client{} = client, family, method, path, params, opts \\ []) do
    host = host!(opts, family)

    case Keyword.get(opts, :body, :form) do
      :form -> build_form(client, family, host, method, path, params)
      :json -> build_json(client, family, host, method, path, params)
      other -> raise ArgumentError, ":body must be :form or :json, got: #{inspect(other)}"
    end
  end

  # A host is where a request goes, not how its body reads. Amap pairs the two
  # most of the time — `restapi.amap.com` answers the flat envelope, `tsapi.amap.com`
  # the Falcon one — but not always: `/v4/direction/bicycling` and
  # `/v4/grasproad/driving` both live on `restapi.amap.com` and answer the Falcon
  # envelope, so a call has to be able to name a host its family does not own.
  # Collected with the other page-versus-service differences in
  defp host!(opts, family) do
    case Keyword.get(opts, :host, family) do
      host when host in [:restapi, :tsapi] ->
        host

      other ->
        raise ArgumentError, "invalid host: #{inspect(other)}; expected :restapi or :tsapi"
    end
  end

  defp build_form(client, family, host, method, path, params) do
    params =
      params
      |> Param.encode()
      |> reject_reserved!()
      |> Keyword.put(:key, client.key)
      |> maybe_sign(client, family, path)

    url = client.base_urls[host] <> path
    encoded = URI.encode_query(params)

    case method do
      :get -> Finch.build(:get, url <> "?" <> encoded)
      :post -> Finch.build(:post, url, @form_headers, encoded)
    end
  end

  defp build_json(_client, family, _host, _method, _path, _params) when family != :tsapi do
    raise ArgumentError,
          "a JSON body is only supported for the :tsapi family, since signing one is not defined"
  end

  defp build_json(%Client{} = client, :tsapi, host, method, path, params) when is_map(params) do
    body =
      params
      |> reject_reserved_map!()
      |> Map.put("key", client.key)
      |> Amap.JSON.encode!()

    json_request(client, host, method, path, body)
  end

  defp build_json(%Client{} = client, :tsapi, host, method, path, params) when is_list(params) do
    if params != [] and Enum.all?(params, &is_map/1) do
      json_request(client, host, method, path, Amap.JSON.encode!(params))
    else
      raise ArgumentError, json_body_message(params)
    end
  end

  defp build_json(%Client{}, :tsapi, _host, _method, _path, params) do
    raise ArgumentError, json_body_message(params)
  end

  # The key goes in the query string as well as the body. A live call with it only in
  # the JSON body answered 10001 INVALID_USER_KEY, so `/v1/track/match` does not read it
  # from there -- and the 轨迹重合度分析 (trajectory overlap) page says nothing about where
  # the key goes. The 轨迹纠偏 page is the first that says: its 通用参数 belong in the
  # query string. Both JSON bodies carry it there, and the object body carries a second
  # copy because that live call needed one.
  defp json_request(client, host, method, path, body) do
    url = client.base_urls[host] <> path <> "?" <> URI.encode_query(key: client.key)

    Finch.build(method, url, @json_headers, body)
  end

  defp json_body_message(params) do
    "a JSON body must be a map or a non-empty list of maps, got: #{inspect(params)}"
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
  @spec send(Client.t(), Client.family(), :get | :post, String.t(), params()) ::
          {:ok, Finch.Response.t()} | {:error, Error.t()}
  @spec send(
          Client.t(),
          Client.family(),
          :get | :post,
          String.t(),
          params(),
          keyword()
        ) ::
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
