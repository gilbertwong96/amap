defmodule Amap.Request do
  @moduledoc """
  Builds and performs Amap HTTP requests.

  Parameters travel as a query string on GET and as an
  `application/x-www-form-urlencoded` body on POST, matching what the API
  accepts. Signing happens on raw values before URL encoding, which is what the
  signature algorithm specifies.

  A call names the host it goes to and, when the endpoint's envelope is not that
  host's default, the envelope it answers. The rest — the base URL, whether to
  sign, and the name of the account key — is read from `Amap.Host`, so none of
  those axes is inferred from another.
  """

  alias Amap.{Client, Error, Host, Param, Signature}

  @form_headers [{"content-type", "application/x-www-form-urlencoded"}]
  @json_headers [{"content-type", "application/json"}]
  @request_options [:envelope, :body]

  # Reserved for every host rather than only the signing ones: a caller who passes
  # `sig` means the client's, and the client never injects one where the host does
  # not sign — sending theirs instead would be guessing at their intent.
  @reserved_sig "sig"

  @typedoc """
  The parameters of a call: the map a form body or the one JSON object
  `track_match` sends, a non-empty list of maps for the JSON array
  `/v4/grasproad/driving` sends, or a keyword list.
  """
  @type params :: Amap.JSON.props() | [Amap.JSON.props()] | keyword()

  @doc """
  Builds a Finch request for the given call.

  `host` names the destination — one of `Amap.Host.names()`. `envelope:` names
  the response envelope when the endpoint is not the host's default: the `/v4/`
  generation on `restapi.amap.com` answers the Falcon envelope, so
  `/v4/direction/bicycling` is built as host `:restapi` with `envelope: :tsapi`.
  A host that does not answer the named envelope raises `ArgumentError` rather
  than falling back.

  The account key is always injected, under the name the host gives it (`key`
  everywhere today except `et-api`, which says `clientKey`), so the key
  parameter and `sig` are reserved: a caller-supplied copy raises, because the
  SDK cannot tell which one the caller meant. `sig` is added only where the
  host's envelope is signed: the Falcon documentation never mentions digital
  signatures, and neither do the `/v4/` pages on the Web service host, so
  signing those would be guessing.

  `body: :json` sends the parameters as a JSON document instead of a form: an
  object for `/v1/track/match`, and a non-empty list of objects for
  `/v4/grasproad/driving`, whose body is a JSON array. It keeps the map's shape —
  nested objects stay nested, because `Param.encode/1` would flatten them into
  string pairs — and is only supported where the request is not signed: signing a
  JSON body is not defined, and sending one unsigned to an envelope that expects
  signatures would be worse than refusing. A JSON value that is neither an object
  nor a non-empty list of objects is refused, so the guarantee stays narrow.

  `opts` takes `:envelope` and `:body` only; anything else raises `ArgumentError`,
  with the removed `:host:` named. The old shape pointed a call at a host the
  positional argument now names, so ignoring it would misroute the call silently.
  """
  @spec build(Client.t(), Host.name(), :get | :post, String.t(), params(), keyword()) ::
          Finch.Request.t()
  def build(%Client{} = client, host, method, path, params, opts \\ []) do
    validate_opts!(opts)
    host = Host.describe(host, Keyword.get(opts, :envelope))
    refuse_unbuildable!(host)

    case Keyword.get(opts, :body, :form) do
      :form -> build_form(client, host, method, path, params)
      :json -> build_json(client, host, method, path, params)
      other -> raise ArgumentError, ":body must be :form or :json, got: #{inspect(other)}"
    end
  end

  defp validate_opts!(opts) do
    case Keyword.keys(opts) -- @request_options do
      [] -> :ok
      unknown -> raise ArgumentError, option_message(unknown)
    end
  end

  # The removed `:host` gets its own message rather than the generic one: a call site
  # left over from the old shape would otherwise be sent to the positional host while
  # the caller believed the ignored option won.
  defp option_message(unknown) do
    if :host in unknown do
      "the :host option was removed: pass the host as the second argument of Amap.request/6, " <>
        "and name the envelope with :envelope when the endpoint's is not the host's default"
    else
      "unknown option(s): #{inspect(unknown)}; expected #{inspect(@request_options)}"
    end
  end

  # `:digest` is described because the page states the shape, but the page gives no
  # algorithm — only 使用说明's 「根据授权文档进行动态鉴权访问」, which points at the
  # commercial grant's own document — so a request that would need it cannot be built
  # honestly.
  defp refuse_unbuildable!(%Host{auth: :digest} = host) do
    raise ArgumentError,
          "cannot build a request for the #{inspect(host.name)} host: it authenticates with " <>
            "#{host.key_param} + timestamp + digest, and the digest algorithm is not public"
  end

  defp refuse_unbuildable!(%Host{}), do: :ok

  defp build_form(client, %Host{} = host, method, path, params) do
    params =
      params
      |> Param.encode()
      |> reject_reserved!(host)
      |> put_key(client, host)
      |> maybe_sign(client, host)

    url = base_url(client, host) <> path
    encoded = URI.encode_query(params)

    case method do
      :get -> Finch.build(:get, url <> "?" <> encoded)
      :post -> Finch.build(:post, url, @form_headers, encoded)
    end
  end

  defp build_json(_client, %Host{auth: :signature} = host, _method, _path, _params) do
    raise ArgumentError,
          "a JSON body is only supported where the request is not signed: the " <>
            "#{inspect(host.name)} host signs its requests, and signing a JSON body " <>
            "is not defined"
  end

  defp build_json(%Client{} = client, %Host{} = host, method, path, params) when is_map(params) do
    body =
      params
      |> reject_reserved_map!(host)
      |> Map.put(host.key_param, client.key)
      |> Amap.JSON.encode!()

    json_request(client, host, method, path, body)
  end

  defp build_json(%Client{} = client, %Host{} = host, method, path, params)
       when is_list(params) do
    if params != [] and Enum.all?(params, &is_map/1) do
      json_request(client, host, method, path, Amap.JSON.encode!(params))
    else
      raise ArgumentError, json_body_message(params)
    end
  end

  defp build_json(%Client{}, %Host{}, _method, _path, params) do
    raise ArgumentError, json_body_message(params)
  end

  # The key goes in the query string as well as the body. A live call with it only in
  # the JSON body answered 10001 INVALID_USER_KEY, so `/v1/track/match` does not read it
  # from there -- and the 轨迹重合度分析 (trajectory overlap) page says nothing about where
  # the key goes. The 轨迹纠偏 page is the first that says: its 通用参数 belong in the
  # query string. Both JSON bodies carry it there, and the object body carries a second
  # copy because that live call needed one.
  defp json_request(client, %Host{} = host, method, path, body) do
    url =
      base_url(client, host) <> path <> "?" <> URI.encode_query([{host.key_param, client.key}])

    Finch.build(method, url, @json_headers, body)
  end

  defp json_body_message(params) do
    "a JSON body must be a map or a non-empty list of maps, got: #{inspect(params)}"
  end

  # Rejected rather than resolved by a precedence rule, because no rule here can
  # be right. The injection below adds the host's key parameter under the name the
  # host gives it, and a caller's copy would be *joined* rather than replaced: the
  # wire carries two entries, server-side parsing keeps the caller's value, and
  # the signature covers both in an order a server may read differently. The
  # failure reaches the caller as `invalid_key` or `invalid_user_signature` and
  # traces to nothing they configured.
  #
  # Reachable despite being contradictory — Amap's own documentation lists `key`
  # in every example parameter table, so copying one is plausible.
  defp reject_reserved!(params, %Host{} = host) do
    case Enum.find(reserved(host), &List.keymember?(params, &1, 0)) do
      nil ->
        params

      reserved ->
        raise ArgumentError,
              "invalid request parameter #{inspect(reserved)}: the client supplies it, so " <>
                "passing it would put two #{reserved} values on the wire; remove it from " <>
                "the parameters"
    end
  end

  defp reserved(%Host{key_param: key_param}), do: [key_param, @reserved_sig]

  @doc """
  Sends a request and normalizes transport-level outcomes.

  An HTTP status other than 200 is reported as `:unexpected_response`: Amap
  signals its own failures in the body with a 200 status, so anything else came
  from a proxy or gateway rather than the API.
  """
  @spec send(Client.t(), Host.name(), :get | :post, String.t(), params()) ::
          {:ok, Finch.Response.t()} | {:error, Error.t()}
  @spec send(
          Client.t(),
          Host.name(),
          :get | :post,
          String.t(),
          params(),
          keyword()
        ) ::
          {:ok, Finch.Response.t()} | {:error, Error.t()}
  def send(%Client{} = client, host, method, path, params, opts \\ []) do
    result =
      client
      |> build(host, method, path, params, opts)
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

  # The same rule as `reject_reserved!/2`, for a JSON body: there the parameters
  # are a map rather than a list of string pairs, so the lookup differs but the
  # reason does not.
  defp reject_reserved_map!(params, %Host{} = host) do
    case Enum.find(reserved(host), &Map.has_key?(params, &1)) do
      nil ->
        params

      reserved ->
        raise ArgumentError,
              "invalid request parameter #{inspect(reserved)}: the client supplies it, so " <>
                "passing it would put two #{reserved} values on the wire; remove it from " <>
                "the parameters"
    end
  end

  # `List.keystore/4` rather than `Keyword.put/3` because the key parameter's name
  # is a string here, as `Param.encode/1`'s keys are — and the caller's copy was
  # just rejected, so this always appends.
  defp put_key(params, %Client{key: key}, %Host{key_param: key_param}) do
    List.keystore(params, key_param, 0, {key_param, key})
  end

  # A client carries a copy of the base URLs so a test server or a proxy can
  # replace them; the descriptor supplies the default for a host the map omits.
  defp base_url(%Client{base_urls: base_urls}, %Host{name: name, base_url: default}) do
    Map.get(base_urls || %{}, name, default)
  end

  defp maybe_sign(params, %Client{private_key: nil}, _host), do: params

  defp maybe_sign(params, %Client{private_key: private_key}, %Host{auth: :signature}) do
    Keyword.put(params, :sig, Signature.sign(params, private_key))
  end

  defp maybe_sign(params, %Client{}, %Host{}), do: params
end
